"""Classe MovimentacaoEquipamento - EduFix.

Transferencia de um bem entre setores. Espelha a tabela movimentacao_equipamento:
enquanto a situacao for 'em_transito' o bem esta "em transito" e NAO pode ter outra
movimentacao aberta (no banco, a coluna virtual chave_aberta + UNIQUE garante isso).
Ao concluir, o Equipamento troca de setor; ao cancelar, nada muda.
"""
from __future__ import annotations

import itertools
from datetime import datetime, timedelta
from typing import Optional, TYPE_CHECKING

if TYPE_CHECKING:
    from equipamento import Equipamento
    from setor import Setor
    from usuario import Usuario

SITUACOES = ("em_transito", "concluida", "cancelada")
SITUACOES_FINAIS = ("concluida", "cancelada")


class MovimentacaoEquipamento:
    _sequencia = itertools.count(1)

    def __init__(
        self,
        id_movimentacao: Optional[int],
        equipamento: "Equipamento",
        setor_origem: Optional["Setor"],
        setor_destino: "Setor",
        responsavel: Optional["Usuario"] = None,
        observacao: str = "",
        data_inicio: Optional[datetime] = None,
        data_conclusao: Optional[datetime] = None,
        situacao: str = "em_transito",
    ):
        if situacao not in SITUACOES:
            raise ValueError(f"Situacao invalida. Use: {', '.join(SITUACOES)}.")
        if setor_destino is None:
            raise ValueError("Informe o setor de destino.")
        if setor_origem is not None and setor_origem is setor_destino:
            raise ValueError("O setor de destino deve ser diferente do de origem.")
        observacao = (observacao or "").strip()
        if len(observacao) > 255:
            raise ValueError("Observacao muito longa (maximo 255 caracteres).")
        self.id_movimentacao = id_movimentacao if id_movimentacao is not None \
            else next(self._sequencia)
        self.equipamento = equipamento
        self.setor_origem = setor_origem
        self.setor_destino = setor_destino
        self.responsavel = responsavel
        self.observacao = observacao
        self.data_inicio = data_inicio or datetime.now()
        self.data_conclusao = data_conclusao
        self.situacao = situacao
        if situacao == "em_transito" and data_conclusao is not None:
            raise ValueError("Movimentacao em transito nao tem data de conclusao.")
        if situacao in SITUACOES_FINAIS and data_conclusao is None:
            self.data_conclusao = self.data_inicio
        if self.data_conclusao is not None and self.data_conclusao < self.data_inicio:
            raise ValueError("data_conclusao anterior a data_inicio.")   # chk_mov_datas

    # ------------------------------------------------------- colunas do banco
    @property
    def id_equipamento(self) -> int:
        return self.equipamento.id_equipamento

    @property
    def id_setor_origem(self) -> Optional[int]:
        return self.setor_origem.id_setor if self.setor_origem else None

    @property
    def id_setor_destino(self) -> int:
        return self.setor_destino.id_setor

    @property
    def id_usuario(self) -> Optional[int]:
        return self.responsavel.id_usuario if self.responsavel else None

    # ------------------------------------------------------------- consultas
    @property
    def em_transito(self) -> bool:
        return self.situacao == "em_transito"

    @property
    def duracao(self) -> timedelta:
        """Tempo entre o inicio e a conclusao (ou ate agora, se ainda em transito)."""
        return (self.data_conclusao or datetime.now()) - self.data_inicio

    # --------------------------------------------------------------- acoes
    def concluir(self, quando: Optional[datetime] = None) -> "MovimentacaoEquipamento":
        """Efetiva a transferencia (so quem chama e o Equipamento, que troca de setor)."""
        self._encerrar("concluida", quando)
        return self

    def cancelar(self, quando: Optional[datetime] = None) -> "MovimentacaoEquipamento":
        """Desfaz a movimentacao sem alterar o setor do bem."""
        self._encerrar("cancelada", quando)
        return self

    def _encerrar(self, nova_situacao: str, quando: Optional[datetime]) -> None:
        if not self.em_transito:
            raise RuntimeError(f"Movimentacao ja {self.situacao}.")
        quando = quando or datetime.now()
        if quando < self.data_inicio:
            raise ValueError("data_conclusao anterior a data_inicio.")
        self.situacao = nova_situacao
        self.data_conclusao = quando

    def to_dict(self) -> dict:
        return {"id_movimentacao": self.id_movimentacao, "id_equipamento": self.id_equipamento,
                "id_setor_origem": self.id_setor_origem, "id_setor_destino": self.id_setor_destino,
                "id_usuario": self.id_usuario, "data_inicio": self.data_inicio,
                "data_conclusao": self.data_conclusao, "situacao": self.situacao,
                "observacao": self.observacao}

    def __repr__(self) -> str:
        origem = self.setor_origem.nome if self.setor_origem else "-"
        return (f"<MovimentacaoEquipamento #{self.id_movimentacao} {origem} -> "
                f"{self.setor_destino.nome} {self.situacao}>")
