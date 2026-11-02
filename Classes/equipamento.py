"""Classe Equipamento - EduFix (bem patrimonial).

Centro do modelo: pertence a um Setor e a uma Categoria, acumula Chamados (e, por
eles, Manutencoes) e gera LogPatrimonio a cada mudanca relevante - o mesmo que os
triggers trg_equipamento_auditoria_* fazem no banco.

status, estado_conservacao e localizacao sao SOMENTE LEITURA: so mudam pelos metodos,
para que nenhuma alteracao escape da auditoria.
"""
from __future__ import annotations

from datetime import date, datetime
from typing import Dict, List, Optional, Tuple, TYPE_CHECKING

from categoria import Categoria
from log_patrimonio import LogPatrimonio
from setor import Setor

if TYPE_CHECKING:
    from chamado import Chamado
    from manutencao import Manutencao
    from usuario import Usuario

STATUS_EQUIPAMENTO = ("disponivel", "em_uso", "em_manutencao", "inativo")
# do pior para o melhor (o indice serve para comparar)
CONSERVACAO = ("inutilizavel", "ruim", "regular", "bom", "otimo")


class Equipamento:
    def __init__(
        self,
        id_equipamento: int,
        nome: str,
        descricao: str,
        setor: Setor,
        categoria: Categoria,
        numero_patrimonio: str,
        data_aquisicao: date,
        estado_conservacao: str = "bom",
        status: str = "disponivel",
        localizacao: Optional[str] = None,
        cadastrado_por: Optional["Usuario"] = None,
    ):
        nome = " ".join((nome or "").split())
        if len(nome) < 2:
            raise ValueError("Nome do equipamento muito curto.")
        if not (numero_patrimonio or "").strip():
            raise ValueError("Numero de patrimonio e obrigatorio.")
        if estado_conservacao not in CONSERVACAO:
            raise ValueError(f"Estado de conservacao invalido: {estado_conservacao!r}.")
        if status not in STATUS_EQUIPAMENTO:
            raise ValueError(f"Status invalido: {status!r}.")
        if status == "em_manutencao":
            raise ValueError("Status 'em_manutencao' so e definido por uma manutencao aberta.")
        if isinstance(data_aquisicao, datetime):
            data_aquisicao = data_aquisicao.date()
        if data_aquisicao > date.today():
            raise ValueError("Data de aquisicao no futuro.")
        self.id_equipamento = id_equipamento
        self.nome = nome
        self.descricao = (descricao or "").strip()
        self.numero_patrimonio = numero_patrimonio.strip()
        self.data_aquisicao = data_aquisicao
        self.setor = setor
        self._categoria = categoria
        self._localizacao = " ".join((localizacao or setor.nome).split())
        self._estado_conservacao = estado_conservacao
        self._status = status
        self._movimentacao: Optional[dict] = None
        self._chamados: List["Chamado"] = []
        self._logs: List[LogPatrimonio] = []
        self._ultima_mudanca_conservacao = datetime.now()
        setor._adicionar(self)
        categoria._adicionar(self)
        self._log("CADASTRO", None, self._localizacao, cadastrado_por)

    # ------------------------------------------------------------ leitura
    @property
    def categoria(self) -> str:
        return self._categoria.nome

    @property
    def categoria_obj(self) -> Categoria:
        return self._categoria

    @property
    def localizacao(self) -> str:
        return self._localizacao

    @property
    def status(self) -> str:
        return self._status

    @property
    def estado_conservacao(self) -> str:
        return self._estado_conservacao

    @property
    def indice_conservacao(self) -> int:
        return CONSERVACAO.index(self._estado_conservacao)

    @property
    def em_movimentacao(self) -> bool:
        """True enquanto houver uma movimentacao iniciada e ainda nao concluida."""
        return self._movimentacao is not None

    @property
    def movimentacao_pendente(self) -> Optional[dict]:
        return dict(self._movimentacao) if self._movimentacao else None

    @property
    def chamados(self) -> Tuple["Chamado", ...]:
        return tuple(self._chamados)

    @property
    def chamados_ativos(self) -> Tuple["Chamado", ...]:
        return tuple(c for c in self._chamados if c.ativo)

    @property
    def manutencoes(self) -> Tuple["Manutencao", ...]:
        return tuple(m for c in self._chamados for m in c.manutencoes)

    @property
    def manutencao_aberta(self) -> Optional["Manutencao"]:
        return next((m for m in self.manutencoes if m.em_andamento), None)

    @property
    def logs(self) -> Tuple[LogPatrimonio, ...]:
        return tuple(self._logs)

    @property
    def aceita_novo_chamado(self) -> bool:
        """Mesma regra do trigger trg_chamado_valida_equipamento (45422)."""
        return self._status != "inativo"

    @property
    def idade_em_anos(self) -> float:
        return round((date.today() - self.data_aquisicao).days / 365.25, 1)

    @property
    def custo_total_manutencao(self) -> float:
        return round(sum(m.calcularCustoTotal() for m in self.manutencoes), 2)

    # --------------------------------------------------------- internos
    @staticmethod
    def _quem(usuario: Optional["Usuario"]) -> str:
        return f"{usuario.nome} (id {usuario.id_usuario})" if usuario else "sistema"

    def _log(self, acao, anterior, novo, usuario=None) -> LogPatrimonio:
        reg = LogPatrimonio(None, self.id_equipamento, self.nome, acao,
                            anterior, novo, self._quem(usuario))
        self._logs.append(reg)
        return reg

    def _registrar_chamado(self, chamado: "Chamado") -> None:
        if chamado not in self._chamados:
            self._chamados.append(chamado)

    @staticmethod
    def _exigir_patrimonio(usuario: Optional["Usuario"]) -> None:
        if usuario is not None and not usuario.possui_permissao("gerenciar_patrimonio"):
            raise PermissionError("Apenas administradores com permissao de patrimonio "
                                  "podem alterar bens.")

    def _mudar_status(self, novo: str, usuario=None) -> bool:
        if novo == self._status:
            return False
        self._log("MUDANCA_STATUS", self._status, novo, usuario)
        self._status = novo
        return True

    def _sincronizar_status(self, usuario: Optional["Usuario"] = None) -> bool:
        """Equivale a procedure sp_sincronizar_equipamento: com manutencao sem data_fim
        o bem fica 'em_manutencao'; terminada a ultima, volta a 'disponivel'.
        Bem inativo nunca e reativado por aqui."""
        if self._status == "inativo":
            return False
        if self.manutencao_aberta is not None:
            return self._mudar_status("em_manutencao", usuario)
        if self._status == "em_manutencao":
            return self._mudar_status("disponivel", usuario)
        return False

    def _revisar_baixa(self, usuario: Optional["Usuario"] = None) -> bool:
        """Bem 'inutilizavel' sem chamado ativo nem manutencao aberta e baixado (inativo)."""
        if (self._estado_conservacao == "inutilizavel" and self._status != "inativo"
                and not self.chamados_ativos and self.manutencao_aberta is None):
            return self._mudar_status("inativo", usuario)
        return False

    # ------------------------------------------------------- metodos UML
    def atualizarEstadoConservacao(
        self, novo_estado: str, usuario: Optional["Usuario"] = None,
        motivo: Optional[str] = None, quando: Optional[datetime] = None,
    ) -> Dict[str, Tuple[str, str]]:
        """Muda o estado de conservacao e devolve o que mudou ({} se nada mudou).
        Regras: valor valido; bem em transito nao e alterado; melhora de 2 ou mais
        niveis so com manutencao CONCLUIDA depois da ultima avaliacao; 'inutilizavel'
        baixa o bem (inativo) assim que nao houver chamado ativo/manutencao aberta."""
        if novo_estado not in CONSERVACAO:
            raise ValueError(f"Estado invalido. Use: {', '.join(CONSERVACAO)}.")
        self._exigir_patrimonio(usuario)
        if novo_estado == self._estado_conservacao:
            return {}
        if self.em_movimentacao:
            raise RuntimeError("Bem em movimentacao: conclua ou cancele antes de reavaliar.")
        novo_idx = CONSERVACAO.index(novo_estado)
        if novo_idx - self.indice_conservacao >= 2:
            houve_reparo = any(m.data_fim and m.data_fim >= self._ultima_mudanca_conservacao
                               for m in self.manutencoes)
            if not houve_reparo:
                raise ValueError("Melhora de 2+ niveis exige manutencao concluida desde a "
                                 "ultima avaliacao.")
        if novo_estado in ("ruim", "inutilizavel") and not (motivo or "").strip():
            raise ValueError("Informe o motivo ao classificar o bem como ruim/inutilizavel.")
        antigo = self._estado_conservacao
        self._log("MUDANCA_CONSERVACAO", antigo, novo_estado, usuario)
        self._estado_conservacao = novo_estado
        self._ultima_mudanca_conservacao = quando or datetime.now()
        mudancas = {"estado_conservacao": (antigo, novo_estado)}
        status_antes = self._status
        self._revisar_baixa(usuario)
        if self._status != status_antes:
            mudancas["status"] = (status_antes, self._status)
        return mudancas

    def atualizarLocalizacao(self, nova_localizacao: str,
                             usuario: Optional["Usuario"] = None) -> Optional[Tuple[str, str]]:
        """CORRIGE onde o bem esta (sala/descricao). Nao troca de setor e nao e uma
        movimentacao - para mudar de setor use registrarMovimentacao. Gera
        TRANSFERENCIA no log, como o trigger do banco. Devolve (antiga, nova) ou None."""
        self._exigir_patrimonio(usuario)
        nova = " ".join((nova_localizacao or "").split())
        if len(nova) < 2:
            raise ValueError("Localizacao invalida.")
        if self.em_movimentacao:
            raise RuntimeError("Bem em movimentacao: a localizacao so muda ao concluir.")
        if self._status == "inativo":
            raise RuntimeError("Bem inativo (baixado) nao tem localizacao atualizada.")
        if nova == self._localizacao:
            return None
        antiga, self._localizacao = self._localizacao, nova
        self._log("TRANSFERENCIA", antiga, nova, usuario)
        return antiga, nova

    def registrarMovimentacao(
        self, destino: Optional[Setor] = None, usuario: Optional["Usuario"] = None,
        acao: str = "iniciar", observacao: str = "", quando: Optional[datetime] = None,
    ) -> dict:
        """Controla a MOVIMENTACAO do bem entre setores (e informa se ele esta em transito):
          acao='iniciar'  -> abre a movimentacao (bem passa a em_movimentacao);
          acao='concluir' -> efetiva: troca de setor, atualiza localizacao e grava
                             TRANSFERENCIA no log;
          acao='cancelar' -> desfaz sem alterar nada.
        Nao move bem inativo, em manutencao ou ja em transito."""
        if acao not in ("iniciar", "concluir", "cancelar"):
            raise ValueError("acao deve ser 'iniciar', 'concluir' ou 'cancelar'.")
        self._exigir_patrimonio(usuario)
        agora = quando or datetime.now()

        if acao == "iniciar":
            if self.em_movimentacao:
                raise RuntimeError("Este bem ja esta em movimentacao.")
            if destino is None or not isinstance(destino, Setor):
                raise ValueError("Informe o setor de destino.")
            if destino is self.setor:
                raise ValueError("O destino e o proprio setor atual.")
            if self._status in ("inativo", "em_manutencao"):
                raise RuntimeError(f"Bem {self._status} nao pode ser movimentado.")
            self._movimentacao = {"origem": self.setor, "destino": destino,
                                  "responsavel": usuario, "inicio": agora,
                                  "observacao": (observacao or "").strip()}
            return {"em_movimentacao": True, "origem": self.setor.nome, "destino": destino.nome}

        mov = self._movimentacao
        if mov is None:
            raise RuntimeError("Nao ha movimentacao em andamento.")
        self._movimentacao = None
        if acao == "cancelar":
            return {"em_movimentacao": False, "cancelada": True,
                    "origem": mov["origem"].nome, "destino": mov["destino"].nome}

        if self._status in ("inativo", "em_manutencao"):  # mudou durante o transito
            self._movimentacao = mov
            raise RuntimeError(f"Bem ficou {self._status}; cancele a movimentacao.")
        mov["origem"]._remover(self)
        mov["destino"]._adicionar(self)
        self.setor = mov["destino"]
        antiga, self._localizacao = self._localizacao, mov["destino"].nome
        if antiga != self._localizacao:
            self._log("TRANSFERENCIA", antiga, self._localizacao, usuario or mov["responsavel"])
        return {"em_movimentacao": False, "origem": mov["origem"].nome,
                "destino": mov["destino"].nome, "duracao": agora - mov["inicio"]}

    # ---------------------------------------------------------- extras
    def definir_em_uso(self, em_uso: bool, usuario: Optional["Usuario"] = None) -> bool:
        """Alterna disponivel <-> em_uso (os demais status sao automaticos)."""
        if self._status not in ("disponivel", "em_uso"):
            raise RuntimeError(f"Bem {self._status}: nao pode mudar para em uso/disponivel.")
        self._exigir_patrimonio(usuario)
        return self._mudar_status("em_uso" if em_uso else "disponivel", usuario)

    def marcar_inativo(self, usuario: Optional["Usuario"] = None) -> bool:
        """Baixa do patrimonio. Bloqueado se houver chamado ativo (mesma regra 45409)."""
        self._exigir_patrimonio(usuario)
        if self.chamados_ativos:
            raise RuntimeError("Equipamento com chamado em andamento nao pode ser inativado.")
        if self.manutencao_aberta or self.em_movimentacao:
            raise RuntimeError("Conclua a manutencao/movimentacao antes de inativar.")
        return self._mudar_status("inativo", usuario)

    def reativar(self, usuario: Optional["Usuario"] = None) -> bool:
        self._exigir_patrimonio(usuario)
        if self._status != "inativo":
            return False
        if self._estado_conservacao == "inutilizavel":
            raise RuntimeError("Bem inutilizavel: reavalie a conservacao antes de reativar.")
        return self._mudar_status("disponivel", usuario)

    def pode_ser_excluido(self) -> Tuple[bool, str]:
        """Regra do trigger trg_equipamento_bloqueia_exclusao (45409)."""
        if self.chamados_ativos:
            return False, "Equipamento com chamado em andamento nao pode ser excluido."
        if self.manutencoes:
            return False, "Equipamento com manutencoes registradas nao pode ser excluido. Marque-o como inativo."
        return True, ""

    def resumo(self) -> dict:
        return {"id": self.id_equipamento, "nome": self.nome, "patrimonio": self.numero_patrimonio,
                "categoria": self.categoria, "setor": self.setor.nome,
                "localizacao": self._localizacao, "status": self._status,
                "conservacao": self._estado_conservacao, "em_movimentacao": self.em_movimentacao,
                "chamados_ativos": len(self.chamados_ativos), "idade_anos": self.idade_em_anos,
                "custo_manutencao": self.custo_total_manutencao}

    def __repr__(self) -> str:
        return f"<Equipamento #{self.id_equipamento} {self.nome!r} {self._status}>"
