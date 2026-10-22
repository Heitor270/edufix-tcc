from datetime import date
from typing import Optional

class Equipamento:
    def __init__(
        self,
        id_equipamento: int,
        nome: str,
        descricao: str,
        estado_conservacao: str,
        localizacao: str,
        numero_patrimonio: str,
        categoria: str,
        data_aquisicao: Optional[date] = None,
        status: str = "disponível",
    ):
        self.id_equipamento = id_equipamento
        self.nome = nome
        self.descricao = descricao
        self.estado_conservacao = estado_conservacao
        self.localizacao = localizacao
        self.numero_patrimonio = numero_patrimonio
        self.categoria = categoria
        self.data_aquisicao = data_aquisicao or date.today()
        self.status = status
 
    def atualizarEstadoConservacao(self, novo_estado: str) -> str:
        """Atualiza o estado de conservação do equipamento."""
        self.estado_conservacao = novo_estado
        return f"Estado de conservação atualizado para '{novo_estado}'."
 
    def atualizarLocalizacao(self, nova_localizacao: str) -> str:
        """Atualiza a localização do equipamento."""
        self.localizacao = nova_localizacao
        return f"Localização atualizada para '{nova_localizacao}'."
 
    def registrarMovimentacao(self, origem: str, destino: str) -> str:
        """Registra a movimentação do equipamento de um local para outro."""
        self.localizacao = destino
        return f"Equipamento movido de '{origem}' para '{destino}'."
 
    def consultarHistoricoChamados(self, lista_chamados: list) -> list:
        """Retorna todos os chamados relacionados a este equipamento."""
        return lista_chamados
 
    def validarDisponibilidade(self) -> bool:
        """Verifica se o equipamento está disponível para uso."""
        return self.status == "disponível"
 
    def listarEquipamento(self) -> str:
        """Retorna um resumo rápido do equipamento."""
        return f"[{self.numero_patrimonio}] {self.nome} — {self.status} | {self.localizacao}"
 
    def exibirInfo(self) -> str:
        """Exibe todas as informações do equipamento."""
        return (
            f"ID: {self.id_equipamento}\n"
            f"Nome: {self.nome}\n"
            f"Descrição: {self.descricao}\n"
            f"Patrimônio: {self.numero_patrimonio}\n"
            f"Categoria: {self.categoria}\n"
            f"Estado: {self.estado_conservacao}\n"
            f"Localização: {self.localizacao}\n"
            f"Status: {self.status}\n"
            f"Adquirido em: {self.data_aquisicao}"
        )