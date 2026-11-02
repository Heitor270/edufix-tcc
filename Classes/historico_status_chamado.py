"""Classe HistoricoStatusChamado - EduFix.

Registro IMUTAVEL (append-only) de cada mudanca de status de um chamado. Quem
guarda a regra de quais mudancas sao validas e esta classe (constantes abaixo),
e o Chamado a consulta - assim existe uma unica fonte da verdade.
"""
from __future__ import annotations

import itertools
from datetime import datetime
from typing import Optional, TYPE_CHECKING

if TYPE_CHECKING:
    from chamado import Chamado

STATUS_CHAMADO = ("aberto", "em_analise", "em_execucao", "concluido", "cancelado")
STATUS_ATIVOS = ("aberto", "em_analise", "em_execucao")
STATUS_FINAIS = ("concluido", "cancelado")

# status_atual -> status permitidos em seguida
TRANSICOES_VALIDAS = {
    "aberto":      ("em_analise", "em_execucao", "concluido", "cancelado"),   # concluido direto = botão Finalizar
    "em_analise":  ("em_execucao", "concluido", "cancelado", "aberto"),
    "em_execucao": ("concluido", "cancelado", "em_analise"),
    "concluido":   ("aberto",),     # reabertura (trigger limpa data_fechamento)
    "cancelado":   ("aberto",),
}


class HistoricoStatusChamado:
    _sequencia = itertools.count(1)
    _CAMPOS = ("id_historico", "chamado", "status_anterior", "status_novo",
               "data_alteracao", "observacao", "alterado_por")

    # Declaracao dos atributos (so para o editor/Pylance reconhecer; os valores sao
    # gravados no __init__ com object.__setattr__ porque o registro e imutavel).
    id_historico: int
    chamado: "Chamado"
    status_anterior: Optional[str]
    status_novo: str
    data_alteracao: datetime
    observacao: str
    alterado_por: int

    def __init__(
        self,
        id_historico: Optional[int],
        chamado: "Chamado",
        status_anterior: Optional[str],
        status_novo: str,
        alterado_por: int,
        observacao: str = "",
        data_alteracao: Optional[datetime] = None,
    ):
        if status_novo not in STATUS_CHAMADO:
            raise ValueError(f"Status novo invalido: {status_novo!r}.")
        if status_anterior is None:
            if status_novo != "aberto":
                raise ValueError("O primeiro registro do historico deve ser 'aberto'.")
        else:
            if status_anterior not in STATUS_CHAMADO:
                raise ValueError(f"Status anterior invalido: {status_anterior!r}.")
            if status_novo not in TRANSICOES_VALIDAS[status_anterior]:
                raise ValueError(f"Transicao invalida: {status_anterior} -> {status_novo}.")
        if status_novo == "cancelado" and not (observacao or "").strip():
            raise ValueError("Cancelamento exige uma observacao (motivo).")
        if status_anterior in STATUS_FINAIS and not (observacao or "").strip():
            raise ValueError("Reabertura exige uma observacao (motivo).")
        if not isinstance(alterado_por, int):
            raise TypeError("alterado_por deve ser o id_usuario (int).")
        object.__setattr__(self, "id_historico",
                           id_historico if id_historico is not None else next(self._sequencia))
        object.__setattr__(self, "chamado", chamado)
        object.__setattr__(self, "status_anterior", status_anterior)
        object.__setattr__(self, "status_novo", status_novo)
        object.__setattr__(self, "data_alteracao", data_alteracao or datetime.now())
        object.__setattr__(self, "observacao", (observacao or "").strip())
        object.__setattr__(self, "alterado_por", alterado_por)

    # imutavel: historico nao se edita nem se apaga
    def __setattr__(self, nome, valor):
        raise AttributeError("HistoricoStatusChamado e imutavel (registro de auditoria).")

    def __delattr__(self, nome):
        raise AttributeError("HistoricoStatusChamado e imutavel (registro de auditoria).")

    # ---------------------------------------------------------- consultas
    @property
    def eh_abertura(self) -> bool:
        return self.status_anterior is None

    @property
    def eh_reabertura(self) -> bool:
        return self.status_anterior in STATUS_FINAIS

    @property
    def eh_encerramento(self) -> bool:
        return self.status_novo in STATUS_FINAIS

    @property
    def tempo_no_status_anterior(self):
        """Quanto tempo o chamado ficou no status anterior (timedelta) ou None."""
        itens = self.chamado.historico
        i = next((k for k, h in enumerate(itens) if h is self), None)
        if not i:
            return None
        return self.data_alteracao - itens[i - 1].data_alteracao

    def __str__(self) -> str:
        de = self.status_anterior or "-"
        return (f"[{self.data_alteracao:%d/%m/%Y %H:%M}] chamado #{self.chamado.id_chamado}: "
                f"{de} -> {self.status_novo} (usuario {self.alterado_por})"
                + (f" - {self.observacao}" if self.observacao else ""))

    def __repr__(self) -> str:
        return f"<HistoricoStatusChamado #{self.id_historico} {self.status_anterior}->{self.status_novo}>"
