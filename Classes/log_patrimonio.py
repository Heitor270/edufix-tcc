"""Classe LogPatrimonio - EduFix.

Linha de auditoria do patrimonio. Espelha a tabela log_patrimonio, alimentada no
banco pelos triggers trg_equipamento_auditoria_*. E imutavel e NAO depende do
equipamento continuar existindo (por isso guarda id e nome, sem chave estrangeira).
"""
from __future__ import annotations

import itertools
from datetime import datetime
from typing import Optional

ACOES = ("CADASTRO", "TRANSFERENCIA", "MUDANCA_STATUS", "MUDANCA_CONSERVACAO", "EXCLUSAO")


class LogPatrimonio:
    _sequencia = itertools.count(1)

    # Declaracao dos atributos (so para o editor/Pylance; os valores sao gravados
    # no __init__ com object.__setattr__ porque o registro e imutavel).
    id_log: int
    id_equipamento: int
    nome_equipamento: str
    acao: str
    valor_anterior: Optional[str]
    valor_novo: Optional[str]
    usuario_banco: str
    data_hora: datetime

    def __init__(
        self,
        id_log: Optional[int],
        id_equipamento: int,
        nome_equipamento: str,
        acao: str,
        valor_anterior: Optional[str],
        valor_novo: Optional[str],
        usuario_banco: str,
        data_hora: Optional[datetime] = None,
    ):
        if acao not in ACOES:
            raise ValueError(f"Acao invalida: {acao!r}. Use uma de {ACOES}.")
        if acao == "CADASTRO" and valor_anterior is not None:
            raise ValueError("CADASTRO nao tem valor anterior.")
        if acao == "EXCLUSAO" and valor_novo is not None:
            raise ValueError("EXCLUSAO nao tem valor novo.")
        if acao in ("TRANSFERENCIA", "MUDANCA_STATUS", "MUDANCA_CONSERVACAO") and \
                (valor_anterior is None or valor_novo is None or valor_anterior == valor_novo):
            raise ValueError(f"{acao} exige valor anterior e novo diferentes.")
        if not (usuario_banco or "").strip():
            raise ValueError("usuario_banco e obrigatorio.")
        for k, v in (("id_log", id_log if id_log is not None else next(self._sequencia)),
                     ("id_equipamento", id_equipamento),
                     ("nome_equipamento", nome_equipamento),
                     ("acao", acao),
                     ("valor_anterior", valor_anterior),
                     ("valor_novo", valor_novo),
                     ("usuario_banco", usuario_banco.strip()),
                     ("data_hora", data_hora or datetime.now())):
            object.__setattr__(self, k, v)

    def __setattr__(self, nome, valor):
        raise AttributeError("LogPatrimonio e imutavel (registro de auditoria).")

    def __delattr__(self, nome):
        raise AttributeError("LogPatrimonio e imutavel (registro de auditoria).")

    @property
    def descricao(self) -> str:
        a, n = self.valor_anterior, self.valor_novo
        return {
            "CADASTRO": f"Cadastrado em '{n}'",
            "TRANSFERENCIA": f"Transferido de '{a}' para '{n}'",
            "MUDANCA_STATUS": f"Status: {a} -> {n}",
            "MUDANCA_CONSERVACAO": f"Conservacao: {a} -> {n}",
            "EXCLUSAO": f"Excluido (ultimo status: {a})",
        }[self.acao]

    def __str__(self) -> str:
        return (f"[{self.data_hora:%d/%m/%Y %H:%M:%S}] #{self.id_equipamento} "
                f"{self.nome_equipamento}: {self.descricao} (por {self.usuario_banco})")

    def __repr__(self) -> str:
        return f"<LogPatrimonio #{self.id_log} {self.acao} equip={self.id_equipamento}>"
