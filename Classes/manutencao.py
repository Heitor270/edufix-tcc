"""Classe Manutencao - EduFix.

Servico tecnico executado para resolver um CHAMADO (a manutencao se liga ao
equipamento por meio do chamado, nao diretamente). Enquanto existir manutencao
iniciada e sem data_fim, o equipamento fica 'em_manutencao' - regra que no banco
e aplicada por trg_manutencao_after_* + sp_sincronizar_equipamento.
"""
from __future__ import annotations

import itertools
from datetime import datetime
from typing import Optional, TYPE_CHECKING

if TYPE_CHECKING:
    from chamado import Chamado
    from equipamento import Equipamento
    from usuario import Usuario


class Manutencao:
    _sequencia = itertools.count(1)

    def __init__(
        self,
        id_manutencao: Optional[int],
        chamado: "Chamado",
        descricao_servico: str,
        tecnico_responsavel: str,
        custo: float = 0.0,
        data_inicio: Optional[datetime] = None,
        data_fim: Optional[datetime] = None,
    ):
        if not chamado.registrado:
            raise RuntimeError("Registre a abertura do chamado antes de criar manutencao.")
        if not chamado.ativo:
            raise RuntimeError("Chamado encerrado nao recebe nova manutencao (reabra-o).")
        descricao_servico = (descricao_servico or "").strip()
        if len(descricao_servico) < 5:
            raise ValueError("Descreva o servico (minimo 5 caracteres).")
        tecnico_responsavel = " ".join((tecnico_responsavel or "").split())
        if len(tecnico_responsavel) < 3:
            raise ValueError("Informe o tecnico responsavel.")
        if custo < 0:
            raise ValueError("Custo nao pode ser negativo.")
        if data_fim is not None and data_inicio is None:
            raise ValueError("Manutencao com data_fim precisa de data_inicio.")
        if data_inicio and data_fim and data_fim < data_inicio:
            raise ValueError("data_fim anterior a data_inicio.")
        self.id_manutencao = id_manutencao if id_manutencao is not None else next(self._sequencia)
        self.chamado = chamado
        self.descricao_servico = descricao_servico
        self.tecnico_responsavel = tecnico_responsavel
        self.custo = round(float(custo), 2)
        self.data_inicio = data_inicio
        self.data_fim = data_fim
        self._procedimentos = 0
        chamado._registrar_manutencao(self)

    # ------------------------------------------------------------ leitura
    @property
    def equipamento(self) -> "Equipamento":
        return self.chamado.equipamento

    @property
    def em_andamento(self) -> bool:
        return self.data_inicio is not None and self.data_fim is None

    @property
    def concluida(self) -> bool:
        return self.data_fim is not None

    @property
    def duracao_horas(self) -> float:
        """Horas trabalhadas; se ainda em andamento, ate agora."""
        if self.data_inicio is None:
            return 0.0
        fim = self.data_fim or datetime.now()
        return round((fim - self.data_inicio).total_seconds() / 3600, 2)

    @staticmethod
    def _exigir_permissao(executor: "Usuario") -> None:
        if executor is None or not executor.ativo or not executor.possui_permissao("gerenciar_chamados"):
            raise PermissionError("Apenas administradores ativos com permissao de chamados "
                                  "executam manutencoes.")

    # -------------------------------------------------------- metodos UML
    def iniciarAtendimento(self, executor: "Usuario", quando: Optional[datetime] = None):
        """Inicia o servico. Regras: nao iniciada ainda; chamado ativo; equipamento nao
        inativo, nao em transito e sem outra manutencao aberta. Efeitos: grava
        data_inicio, leva o chamado a 'em_execucao' (passando por 'em_analise' se
        estiver 'aberto', com historico) e coloca o equipamento 'em_manutencao'.
        Devolve o ultimo HistoricoStatusChamado gerado (ou None se nada mudou)."""
        self._exigir_permissao(executor)
        if self.data_inicio is not None:
            raise RuntimeError("Atendimento ja iniciado.")
        ch, eq = self.chamado, self.equipamento
        if not ch.ativo:
            raise RuntimeError("Chamado encerrado: nao e possivel iniciar atendimento.")
        if not eq.aceita_novo_chamado:
            raise RuntimeError("Equipamento inativo nao recebe manutencao.")
        if eq.em_movimentacao:
            raise RuntimeError("Equipamento em movimentacao: conclua antes de iniciar o reparo.")
        outra = eq.manutencao_aberta
        if outra is not None:
            raise RuntimeError(f"Ja existe manutencao #{outra.id_manutencao} em andamento "
                               f"neste equipamento.")
        quando = quando or datetime.now()
        self.data_inicio = quando
        ultimo = None
        if ch.status == "aberto":
            ultimo = ch.atualizarStatus("em_analise", executor, "Atendimento iniciado", quando)
        if ch.status == "em_analise":
            ultimo = ch.atualizarStatus("em_execucao", executor,
                                        f"Manutencao #{self.id_manutencao} iniciada", quando)
        eq._sincronizar_status(executor)
        return ultimo

    def registrarProcedimento(self, procedimento: str, custo_adicional: float = 0.0,
                              quando: Optional[datetime] = None) -> str:
        """Anota um passo do reparo (com carimbo de data/hora) na descricao do servico e
        soma o custo de pecas/servicos. Devolve a linha registrada."""
        if not self.em_andamento:
            raise RuntimeError("So e possivel registrar procedimentos com o atendimento em andamento.")
        procedimento = (procedimento or "").strip()
        if len(procedimento) < 3:
            raise ValueError("Descreva o procedimento.")
        if custo_adicional < 0:
            raise ValueError("Custo adicional nao pode ser negativo.")
        quando = quando or datetime.now()
        if self.data_inicio is None or quando < self.data_inicio:
            raise ValueError("Procedimento anterior ao inicio do atendimento.")
        linha = f"[{quando:%d/%m/%Y %H:%M}] {procedimento}"
        if custo_adicional:
            linha += f" (R$ {custo_adicional:.2f})"
        self.descricao_servico += "\n" + linha
        self.custo = round(self.custo + custo_adicional, 2)
        self._procedimentos += 1
        return linha

    def concluirAtendimento(
        self, executor: "Usuario", estado_conservacao_final: Optional[str] = None,
        observacao: str = "", encerrar_chamado: bool = False,
        quando: Optional[datetime] = None,
    ) -> dict:
        """Finaliza o servico: exige ao menos um procedimento registrado, grava data_fim,
        devolve o equipamento a 'disponivel' e, se informado, reavalia a conservacao.
        Com encerrar_chamado=True ja conclui o chamado. Devolve um resumo."""
        self._exigir_permissao(executor)
        if not self.em_andamento:
            raise RuntimeError("Nao ha atendimento em andamento.")
        if self._procedimentos == 0:
            raise ValueError("Registre ao menos um procedimento antes de concluir.")
        quando = quando or datetime.now()
        if self.data_inicio is None or quando < self.data_inicio:
            raise ValueError("data_fim anterior a data_inicio.")
        eq = self.equipamento
        self.data_fim = quando
        status_antes = eq.status
        eq._sincronizar_status(executor)
        resumo = {"id_manutencao": self.id_manutencao, "horas": self.duracao_horas,
                  "custo_total": self.calcularCustoTotal(),
                  "status_equipamento": (status_antes, eq.status), "conservacao": None,
                  "chamado_encerrado": False}
        if estado_conservacao_final:
            resumo["conservacao"] = eq.atualizarEstadoConservacao(
                estado_conservacao_final, executor,
                motivo=observacao or "Avaliacao apos manutencao", quando=quando)
        if encerrar_chamado:
            self.chamado.encerrarChamado(executor, observacao or "Servico concluido", True, quando)
            resumo["chamado_encerrado"] = True
        return resumo

    def calcularCustoTotal(self, taxa_hora: float = 0.0) -> float:
        """Custo de pecas/servicos + (horas trabalhadas x taxa_hora da mao de obra).
        Apenas calcula - nao altera o objeto."""
        if taxa_hora < 0:
            raise ValueError("taxa_hora nao pode ser negativa.")
        return round(self.custo + self.duracao_horas * taxa_hora, 2)

    def __repr__(self) -> str:
        estado = "concluida" if self.concluida else "em andamento" if self.em_andamento else "agendada"
        return f"<Manutencao #{self.id_manutencao} chamado={self.chamado.id_chamado} {estado}>"
