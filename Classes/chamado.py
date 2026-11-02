"""Classe Chamado - EduFix.

Orquestra o fluxo: o USUARIO abre o chamado sobre um EQUIPAMENTO; cada mudanca de
status vira um HistoricoStatusChamado; as MANUTENCOES sao executadas dentro do chamado.
"""
from __future__ import annotations

import itertools
import unicodedata
from datetime import datetime, timedelta
from typing import List, Optional, Tuple, TYPE_CHECKING

from historico_status_chamado import (
    HistoricoStatusChamado, STATUS_ATIVOS, STATUS_FINAIS, TRANSICOES_VALIDAS)

if TYPE_CHECKING:
    from equipamento import Equipamento
    from manutencao import Manutencao
    from usuario import Usuario

PRIORIDADES = ("baixa", "media", "alta", "critica")
PRAZO_SLA_HORAS = {"critica": 4, "alta": 24, "media": 72, "baixa": 168}

_PALAVRAS = (   # (pontos, termos)  - texto comparado sem acento e em minusculas
    (4, ("fogo", "fumaca", "faisca", "curto circuito", "curto-circuito", "choque",
         "cheiro de queimado", "incendio", "vazamento de gas")),
    (2, ("nao liga", "parou", "quebrad", "travad", "sem energia", "sem agua",
         "nao funciona", "queimou", "estourou", "inoperante")),
    (1, ("lento", "ruido", "falha", "intermitente", "piscando", "vazando",
         "goteira", "emperrad", "barulho")),
)


def _sem_acento(txt: str) -> str:
    return "".join(c for c in unicodedata.normalize("NFD", txt.lower())
                   if unicodedata.category(c) != "Mn")


class Chamado:
    _sequencia = itertools.count(1)

    def __init__(
        self,
        id_chamado: Optional[int],
        usuario: "Usuario",
        equipamento: "Equipamento",
        descricao_problema: str,
        prioridade: Optional[str] = None,
        observacoes: str = "",
        data_abertura: Optional[datetime] = None,
    ):
        if prioridade is not None and prioridade not in PRIORIDADES:
            raise ValueError(f"Prioridade invalida. Use: {', '.join(PRIORIDADES)}.")
        self.id_chamado = id_chamado if id_chamado is not None else next(self._sequencia)
        self.usuario = usuario
        self.equipamento = equipamento
        self.descricao_problema = (descricao_problema or "").strip()
        self.prioridade = prioridade or "media"
        self._prioridade_definida = prioridade is not None
        self.observacoes = (observacoes or "").strip()
        self.status = "aberto"
        self.data_abertura = data_abertura or datetime.now()
        self.data_fechamento: Optional[datetime] = None
        self._historico: List[HistoricoStatusChamado] = []
        self._manutencoes: List["Manutencao"] = []

    # ------------------------------------------------------------ leitura
    @property
    def registrado(self) -> bool:
        return bool(self._historico)

    @property
    def ativo(self) -> bool:
        return self.registrado and self.status in STATUS_ATIVOS

    @property
    def historico(self) -> Tuple[HistoricoStatusChamado, ...]:
        return tuple(self._historico)

    @property
    def manutencoes(self) -> Tuple["Manutencao", ...]:
        return tuple(self._manutencoes)

    def _registrar_manutencao(self, m: "Manutencao") -> None:
        if m not in self._manutencoes:
            self._manutencoes.append(m)

    def criarManutencao(self, descricao_servico: str, tecnico_responsavel: str,
                        custo: float = 0.0) -> "Manutencao":
        """Cria uma Manutencao ja vinculada a este chamado."""
        from manutencao import Manutencao
        return Manutencao(None, self, descricao_servico, tecnico_responsavel, custo)

    @property
    def custo_total(self) -> float:
        return round(sum(m.calcularCustoTotal() for m in self._manutencoes), 2)

    def tempo_atendimento(self, agora: Optional[datetime] = None) -> timedelta:
        fim = self.data_fechamento or agora or datetime.now()
        return fim - self.data_abertura

    @property
    def prazo_sla_horas(self) -> int:
        return PRAZO_SLA_HORAS[self.prioridade]

    def sla_estourado(self, agora: Optional[datetime] = None) -> bool:
        return self.tempo_atendimento(agora).total_seconds() / 3600 > self.prazo_sla_horas

    def _anotar(self, texto: str, quando: datetime) -> None:
        if texto:
            self.observacoes = (self.observacoes + "\n" if self.observacoes else "") \
                + f"[{quando:%d/%m/%Y %H:%M}] {texto}"

    # -------------------------------------------------------- metodos UML
    def registrarAbertura(self, quando: Optional[datetime] = None) -> HistoricoStatusChamado:
        """Efetiva o chamado: valida usuario ativo, equipamento aceito (nao inativo -
        regra 45422), descricao e duplicidade; classifica a prioridade se ela nao foi
        escolhida; vincula o chamado ao usuario e ao equipamento e grava o 1o historico."""
        if self.registrado:
            raise RuntimeError("Chamado ja registrado.")
        if not self.usuario.ativo:
            raise PermissionError("Usuario inativo nao pode abrir chamado.")
        if not self.equipamento.aceita_novo_chamado:
            raise ValueError("Nao e possivel abrir chamado para um equipamento inativo.")
        if len(self.descricao_problema) < 10:
            raise ValueError("Descreva o problema (minimo 10 caracteres).")
        if any(c.usuario is self.usuario and c.ativo for c in self.equipamento.chamados):
            raise ValueError("Voce ja tem um chamado em andamento para este equipamento.")
        self.data_abertura = quando or self.data_abertura
        if not self._prioridade_definida:
            self.classificarPrioridade(_antes_do_registro=True)
        hist = HistoricoStatusChamado(None, self, None, "aberto", self.usuario.id_usuario,
                                      "Chamado aberto", self.data_abertura)
        self._historico.append(hist)
        self.usuario._registrar_chamado(self)
        self.equipamento._registrar_chamado(self)
        return hist

    def classificarPrioridade(self, somente_elevar: bool = True,
                              _antes_do_registro: bool = False) -> str:
        """Define a prioridade a partir de 3 sinais: (1) palavras do problema (risco >
        parada > degradacao), (2) estado de conservacao do bem, (3) reincidencia de
        chamados do mesmo bem nos ultimos 30 dias. Com somente_elevar=True nunca
        reduz uma prioridade ja escolhida. Devolve a prioridade final."""
        if self.registrado and self.status not in ("aberto", "em_analise"):
            raise RuntimeError("So se reclassifica chamado 'aberto' ou 'em_analise'.")
        texto = _sem_acento(self.descricao_problema)
        pontos = max((p for p, termos in _PALAVRAS if any(t in texto for t in termos)), default=0)
        eq = self.equipamento
        pontos += {"ruim": 1, "inutilizavel": 2}.get(eq.estado_conservacao, 0)
        limite = self.data_abertura - timedelta(days=30)
        recentes = sum(1 for c in eq.chamados
                       if c is not self and limite <= c.data_abertura <= self.data_abertura)
        pontos += 2 if recentes >= 4 else 1 if recentes >= 2 else 0
        nova = "critica" if pontos >= 4 else "alta" if pontos >= 2 else "media" if pontos >= 1 else "baixa"
        if somente_elevar and self._prioridade_definida and \
                PRIORIDADES.index(nova) <= PRIORIDADES.index(self.prioridade):
            nova = self.prioridade
        if nova != self.prioridade and self.registrado:
            self._anotar(f"Prioridade {self.prioridade} -> {nova} (classificacao automatica)",
                         datetime.now())
        self.prioridade = nova
        self._prioridade_definida = True
        return nova

    def atualizarStatus(self, novo_status: str, usuario: "Usuario", observacao: str = "",
                        quando: Optional[datetime] = None) -> HistoricoStatusChamado:
        """Muda o status seguindo TRANSICOES_VALIDAS e grava o historico. Permissoes:
        administrador com 'gerenciar_chamados' faz qualquer transicao; o autor do chamado
        so pode CANCELAR enquanto ele estiver 'aberto'. Concluir exige que nao haja
        manutencao em andamento (e observacao se nao houve manutencao). Preenche/limpa
        data_fechamento como o trigger trg_chamado_data_fechamento."""
        if not self.registrado:
            raise RuntimeError("Registre a abertura do chamado primeiro.")
        if not usuario.ativo:
            raise PermissionError("Usuario inativo.")
        if novo_status not in TRANSICOES_VALIDAS:
            raise ValueError(f"Status invalido: {novo_status!r}.")
        if novo_status not in TRANSICOES_VALIDAS[self.status]:
            raise ValueError(f"Transicao invalida: {self.status} -> {novo_status}.")
        eh_gestor = usuario.possui_permissao("gerenciar_chamados")
        if not eh_gestor:
            if not (usuario is self.usuario and novo_status == "cancelado"
                    and self.status == "aberto"):
                raise PermissionError("Voce so pode cancelar o seu proprio chamado enquanto "
                                      "ele estiver aberto.")
        quando = quando or datetime.now()
        if quando < self._historico[-1].data_alteracao:
            raise ValueError("Data anterior a ultima alteracao do historico.")
        observacao = (observacao or "").strip()
        if novo_status in ("em_execucao", "aberto") and not self.equipamento.aceita_novo_chamado:
            raise ValueError("Equipamento inativo: nao e possivel (re)abrir/executar o chamado.")
        if novo_status == "concluido":
            if any(m.em_andamento for m in self._manutencoes):
                raise RuntimeError("Ha manutencao em andamento: conclua-a antes do chamado.")
            if not any(m.concluida for m in self._manutencoes) and not observacao:
                raise ValueError("Concluir sem manutencao exige observacao explicando a solucao.")
        if novo_status == "cancelado" and any(m.em_andamento for m in self._manutencoes):
            raise RuntimeError("Ha manutencao em andamento: conclua-a antes de cancelar.")
        hist = HistoricoStatusChamado(None, self, self.status, novo_status,
                                      usuario.id_usuario, observacao, quando)
        self._historico.append(hist)
        self.status = novo_status
        self.data_fechamento = quando if novo_status in STATUS_FINAIS else None
        self._anotar(observacao, quando)
        if novo_status in STATUS_FINAIS:
            self.equipamento._sincronizar_status(usuario)
            self.equipamento._revisar_baixa(usuario)
        return hist

    def encerrarChamado(self, usuario: "Usuario", observacao: str = "",
                        resolvido: bool = True,
                        quando: Optional[datetime] = None) -> HistoricoStatusChamado:
        """Fecha o chamado: resolvido=True -> 'concluido' (avanca sozinho ate
        'em_execucao' se preciso, deixando historico); resolvido=False -> 'cancelado'
        (motivo obrigatorio). Nao fecha com manutencao em andamento. Devolve o
        historico do encerramento."""
        if not self.ativo:
            raise RuntimeError("Chamado ja encerrado ou nao registrado.")
        if not usuario.possui_permissao("gerenciar_chamados") and usuario is not self.usuario:
            raise PermissionError("Sem permissao para encerrar este chamado.")
        quando = quando or datetime.now()
        if not resolvido:
            return self.atualizarStatus("cancelado", usuario, observacao, quando)
        if any(m.em_andamento for m in self._manutencoes):
            raise RuntimeError("Ha manutencao em andamento: conclua-a antes de encerrar.")
        if self.status == "aberto":
            self.atualizarStatus("em_analise", usuario, "Avanco automatico ao encerrar", quando)
        if self.status == "em_analise":
            self.atualizarStatus("em_execucao", usuario, "Avanco automatico ao encerrar", quando)
        return self.atualizarStatus("concluido", usuario, observacao, quando)

    def resumo(self) -> dict:
        return {"id": self.id_chamado, "usuario": self.usuario.nome,
                "equipamento": self.equipamento.nome, "status": self.status,
                "prioridade": self.prioridade, "sla_horas": self.prazo_sla_horas,
                "sla_estourado": self.sla_estourado(), "manutencoes": len(self._manutencoes),
                "custo_total": self.custo_total, "mudancas_de_status": len(self._historico)}

    def __repr__(self) -> str:
        return f"<Chamado #{self.id_chamado} {self.status} prioridade={self.prioridade}>"
