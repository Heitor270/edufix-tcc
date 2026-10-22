from datetime import date
from typing import Optional

class Manutencao:
    def __init__(
        self,
        id_manutencao: Optional[int],
        id_chamado: Optional[int],
        tecnico_responsavel: str,
        id_equipamento: Optional[int] = None,
        descricao_servico: str = "",
        custo: float = 0.0,
        data_inicio: Optional[date] = None,
        data_fim: Optional[date] = None,
    ):
        self.id_manutencao = id_manutencao
        self.id_chamado = id_chamado
        self.id_equipamento = id_equipamento
        self.tecnico_responsavel = tecnico_responsavel
        self.descricao_servico = descricao_servico
        self.custo = custo
        self.data_inicio = data_inicio
        self.data_fim = data_fim
 
    def iniciarAtendimento(self) -> str:
        """Registra o início do atendimento da manutenção."""
        self.data_inicio = date.today()
        return f"Manutenção #{self.id_manutencao} iniciada em {self.data_inicio}."
 
    def registrarProcedimento(self, descricao: str) -> str:
        """Adiciona um procedimento realizado durante a manutenção."""
        self.descricao_servico += f"\n[{date.today()}] {descricao}"
        return "Procedimento registrado."
 
    def atualizarIntervencao(self, nova_descricao: str) -> str:
        """Atualiza a descrição do serviço realizado."""
        self.descricao_servico = nova_descricao
        return "Intervenção atualizada."
 
    def concluirAtendimento(self) -> str:
        """Conclui a manutenção com data de término."""
        self.data_fim = date.today()
        return f"Manutenção #{self.id_manutencao} concluída em {self.data_fim}."
 
    def calcularCustoTotal(self, custos_adicionais: list[float] = []) -> float:
        """Soma o custo base com custos adicionais e retorna o total."""
        self.custo += sum(custos_adicionais)
        return self.custo
 
    def exibirInfo(self) -> str:
        """Exibe as informações da manutenção."""
        return (
            f"ID Manutenção: {self.id_manutencao}\n"
            f"ID Chamado: {self.id_chamado}\n"
            f"Técnico: {self.tecnico_responsavel}\n"
            f"Descrição: {self.descricao_servico}\n"
            f"Custo: R$ {self.custo:.2f}\n"
            f"Início: {self.data_inicio} | Fim: {self.data_fim}"
        )