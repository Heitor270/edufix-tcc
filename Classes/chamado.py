from datetime import date
from typing import Optional

class Chamado:
    def __init__(
        self,
        id_chamado: Optional[int],
        id_usuario: int,
        id_equipamento: Optional[int] = None,
        prioridade: str = "média",
        descricao_problema: str = "",
        status: str = "aberto",
        observacoes: str = "",
        data_abertura: Optional[date] = None,
        data_fechamento: Optional[date] = None,
    ):
        self.id_chamado = id_chamado
        self.id_usuario = id_usuario
        self.id_equipamento = id_equipamento
        self.prioridade = prioridade
        self.descricao_problema = descricao_problema
        self.status = status
        self.observacoes = observacoes
        self.data_abertura = data_abertura or date.today()
        self.data_fechamento = data_fechamento

    def registrarAbertura(self) -> str:
        """Confirma a abertura do chamado."""
        self.status = "aberto"
        self.data_abertura = date.today()
        return f"Chamado #{self.id_chamado} aberto em {self.data_abertura}."

    def classificarPrioridade(self, prioridade: str) -> str:
        """Define a prioridade do chamado (baixa, média, alta, crítica)."""
        prioridades_validas = ["baixa", "média", "alta", "crítica"]
        if prioridade.lower() in prioridades_validas:
            self.prioridade = prioridade.lower()
            return f"Prioridade definida como '{self.prioridade}'."
        return f"Prioridade inválida. Use: {', '.join(prioridades_validas)}."

    def atualizarStatus(self, novo_status: str) -> str:
        """Atualiza o status do chamado."""
        self.status = novo_status
        return f"Status atualizado para '{self.status}'."

    def registrarInteracao(self, texto: str) -> str:
        """Adiciona uma observação/interação ao chamado."""
        self.observacoes += f"\n[{date.today()}] {texto}"
        return "Interação registrada."

    def encerrarChamado(self) -> str:
        """Encerra o chamado definindo status e data de fechamento."""
        self.status = "fechado"
        self.data_fechamento = date.today()
        return f"Chamado #{self.id_chamado} encerrado em {self.data_fechamento}."

    def calcularTempoResolucao(self) -> int:
        """Calcula em dias o tempo de resolução do chamado.
        Se ainda aberto, calcula até hoje."""
        referencia = self.data_fechamento or date.today()
        return (referencia - self.data_abertura).days

    def obterResumoOperacional(self) -> str:
        """Retorna um resumo do chamado."""
        return (
            f"Chamado #{self.id_chamado}\n"
            f"Status: {self.status}\n"
            f"Prioridade: {self.prioridade}\n"
            f"Aberto em: {self.data_abertura}\n"
            f"Fechado em: {self.data_fechamento or 'Em aberto'}\n"
            f"Tempo de resolução: {self.calcularTempoResolucao()} dia(s)"
        )

    def exibirInfo(self) -> str:
        """Exibe todas as informações do chamado."""
        return (
            f"ID Chamado: {self.id_chamado}\n"
            f"Descrição: {self.descricao_problema}\n"
            f"Status: {self.status}\n"
            f"Prioridade: {self.prioridade}\n"
            f"Observações: {self.observacoes}\n"
            f"Abertura: {self.data_abertura} | Fechamento: {self.data_fechamento}"
        )