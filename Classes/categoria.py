"""Classe Categoria - EduFix. Agrupa equipamentos por tipo (Informatica, Mobiliario...)."""
from __future__ import annotations

from typing import Dict, List, Optional, Union, TYPE_CHECKING

if TYPE_CHECKING:
    from equipamento import Equipamento
    from setor import Setor

CATEGORIAS_PADRAO = ("Informatica", "Mobiliario", "Climatizacao", "Eletrodomestico", "Outro")


class Categoria:
    def __init__(self, id_categoria: int, nome: str):
        nome = " ".join((nome or "").split())
        if len(nome) < 2:
            raise ValueError("Nome da categoria deve ter pelo menos 2 caracteres.")
        self.id_categoria = id_categoria
        self.nome = nome
        self._equipamentos: List["Equipamento"] = []

    # chamados pelo Equipamento (mantem os dois lados da associacao coerentes)
    def _adicionar(self, equipamento: "Equipamento") -> None:
        if equipamento not in self._equipamentos:
            self._equipamentos.append(equipamento)

    def _remover(self, equipamento: "Equipamento") -> None:
        if equipamento in self._equipamentos:
            self._equipamentos.remove(equipamento)

    def listarBens(
        self,
        setor: Optional["Setor"] = None,
        status: Optional[str] = None,
        estado_conservacao: Optional[str] = None,
        ordenar_por: str = "nome",
        agrupar_por_setor: bool = False,
    ) -> Union[List["Equipamento"], Dict[str, List["Equipamento"]]]:
        """Bens desta categoria, com filtros (setor/status/conservacao), ordenacao
        (nome, numero_patrimonio, data_aquisicao, estado_conservacao) e, opcionalmente,
        agrupados por setor ({nome_do_setor: [bens]})."""
        chaves = {
            "nome": lambda e: e.nome.lower(),
            "numero_patrimonio": lambda e: e.numero_patrimonio,
            "data_aquisicao": lambda e: e.data_aquisicao,
            "estado_conservacao": lambda e: e.indice_conservacao,
        }
        if ordenar_por not in chaves:
            raise ValueError(f"ordenar_por invalido. Use: {', '.join(chaves)}.")
        itens = [e for e in self._equipamentos
                 if (setor is None or e.setor is setor)
                 and (status is None or e.status == status)
                 and (estado_conservacao is None or e.estado_conservacao == estado_conservacao)]
        itens.sort(key=chaves[ordenar_por])
        if not agrupar_por_setor:
            return itens
        grupos: Dict[str, List["Equipamento"]] = {}
        for e in itens:
            grupos.setdefault(e.setor.nome, []).append(e)
        return grupos

    def __len__(self) -> int:
        return len(self._equipamentos)

    def __repr__(self) -> str:
        return f"<Categoria #{self.id_categoria} {self.nome!r} bens={len(self)}>"
