from datetime import date
from typing import Optional

class HistoricoStatusChamado:
    def __init__(
        self,
        id_historico: Optional[int],
        id_chamado: int,
        id_usuario: int,
        status_novo: str,
        status_anterior: Optional[str] = None,
        data_alteracao: Optional[date] = None,
        observacao: str = "",
    ):
        self.id_historico = id_historico
        self.id_chamado = id_chamado
        self.id_usuario = id_usuario
        self.status_anterior = status_anterior
        self.status_novo = status_novo
        self.data_alteracao = data_alteracao or date.today()
        self.observacao = observacao

    def exibirInfo(self) -> str:
        return (
            f"ID Histórico: {self.id_historico}\n"
            f"Chamado: #{self.id_chamado}\n"
            f"Alterado por usuário: #{self.id_usuario}\n"
            f"Status anterior: {self.status_anterior or 'N/A'}\n"
            f"Status novo: {self.status_novo}\n"
            f"Data: {self.data_alteracao}\n"
            f"Observação: {self.observacao}"
        )