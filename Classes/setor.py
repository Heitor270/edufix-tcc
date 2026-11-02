"""Classe Setor - EduFix. Local fisico da escola onde os bens ficam (sala, laboratorio...)."""
from __future__ import annotations

from typing import Dict, List, Optional, Union, TYPE_CHECKING

if TYPE_CHECKING:
    from categoria import Categoria
    from equipamento import Equipamento


class Setor:
    AGRUPAMENTOS = ("status", "categoria", "estado_conservacao")

    def __init__(self, id_setor: int, nome: str):
        nome = " ".join((nome or "").split())
        if len(nome) < 2:
            raise ValueError("Nome do setor deve ter pelo menos 2 caracteres.")
        self.id_setor = id_setor
        self.nome = nome
        self._equipamentos: List["Equipamento"] = []

    def _adicionar(self, equipamento: "Equipamento") -> None:
        if equipamento not in self._equipamentos:
            self._equipamentos.append(equipamento)

    def _remover(self, equipamento: "Equipamento") -> None:
        if equipamento in self._equipamentos:
            self._equipamentos.remove(equipamento)

    def _filtrar(self, status, categoria, incluir_em_transito):
        itens = []
        for e in self._equipamentos:
            if status is not None and e.status != status:
                continue
            if categoria is not None and e.categoria != categoria.nome:
                continue
            if not incluir_em_transito and e.em_movimentacao:
                continue
            itens.append(e)
        return itens

    def listarBens(
        self,
        status: Optional[str] = None,
        categoria: Optional["Categoria"] = None,
        ordenar_por: str = "nome",
        incluir_em_transito: bool = True,
    ) -> List["Equipamento"]:
        """Bens do setor, filtrados por status/categoria e ordenados. Bens que estao
        saindo do setor (em movimentacao) aparecem por padrao; use
        incluir_em_transito=False para ve-los fora da lista."""
        chaves = {
            "nome": lambda e: e.nome.lower(),
            "numero_patrimonio": lambda e: e.numero_patrimonio,
            "data_aquisicao": lambda e: e.data_aquisicao,
            "estado_conservacao": lambda e: (e.indice_conservacao, e.nome.lower()),
        }
        if ordenar_por not in chaves:
            raise ValueError(f"ordenar_por invalido. Use: {', '.join(chaves)}.")
        return sorted(self._filtrar(status, categoria, incluir_em_transito), key=chaves[ordenar_por])

    def contarBens(
        self,
        agrupar_por: Optional[str] = None,
        status: Optional[str] = None,
        categoria: Optional["Categoria"] = None,
        incluir_em_transito: bool = True,
    ) -> Union[int, Dict[str, int]]:
        """Sem agrupar_por devolve o total (int). Com agrupar_por ('status', 'categoria'
        ou 'estado_conservacao') devolve {valor: quantidade}, do maior para o menor."""
        itens = self._filtrar(status, categoria, incluir_em_transito)
        if agrupar_por is None:
            return len(itens)
        if agrupar_por not in self.AGRUPAMENTOS:
            raise ValueError(f"agrupar_por invalido. Use: {', '.join(self.AGRUPAMENTOS)}.")
        contagem: Dict[str, int] = {}
        for e in itens:
            chave = getattr(e, agrupar_por)
            contagem[chave] = contagem.get(chave, 0) + 1
        return dict(sorted(contagem.items(), key=lambda kv: (-kv[1], kv[0])))

    def __len__(self) -> int:
        return len(self._equipamentos)

    def __repr__(self) -> str:
        return f"<Setor #{self.id_setor} {self.nome!r} bens={len(self)}>"
