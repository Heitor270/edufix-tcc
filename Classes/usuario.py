from datetime import date
from typing import Optional
from chamado import Chamado
 
class Usuario:
    def __init__(
        self,
        id_usuario: int,
        nome: str,
        senha: str,
        email: str,
        telefone: str,
        cpf: str,
        data_nascimento: date,
        ativo: bool = True,
        data_cadastro: Optional[date] = None,
        ultimo_login: Optional[date] = None,
    ):
        self.id_usuario = id_usuario
        self.nome = nome
        self.senha = senha
        self.email = email
        self.telefone = telefone
        self.cpf = cpf
        self.data_nascimento = data_nascimento
        self.ativo = ativo
        self.data_cadastro = data_cadastro or date.today()
        self.ultimo_login = ultimo_login
 
    def registrarChamado(self, descricao: str, prioridade: str, id_equipamento: Optional[int] = None) -> "Chamado":
        chamado = Chamado(
            id_chamado=None,
            id_usuario=self.id_usuario,      
            id_equipamento=id_equipamento,   
            prioridade=prioridade,
            descricao_problema=descricao,
        )
        return chamado
 
    def consultarChamado(self, lista_chamados: list, id_chamado: int) -> Optional["Chamado"]:
        """Busca e retorna um chamado pelo ID dentro de uma lista."""
        for chamado in lista_chamados:
            if chamado.id_chamado == id_chamado:
                return chamado
        return None
 
    def acompanharChamado(self, chamado: "Chamado") -> str:
        """Retorna o status atual de um chamado."""
        return f"Chamado #{chamado.id_chamado} — Status: {chamado.status}"
 
    def validarIdentidade(self, cpf_informado: str) -> bool:
        """Valida se o CPF informado corresponde ao do usuário."""
        return self.cpf == cpf_informado
 
    def exibirInfo(self) -> str:
        """Retorna uma string com as informações do usuário."""
        return (
            f"ID: {self.id_usuario}\n"
            f"Nome: {self.nome}\n"
            f"Email: {self.email}\n"
            f"Telefone: {self.telefone}\n"
            f"CPF: {self.cpf}\n"
            f"Ativo: {self.ativo}\n"
            f"Data de Cadastro: {self.data_cadastro}\n"
            f"Último Login: {self.ultimo_login}"
        )
 
    def normalizarDados(self):
        """Normaliza os dados do usuário (remove espaços, padroniza capitalização)."""
        self.nome = self.nome.strip().title()
        self.email = self.email.strip().lower()
        self.cpf = self.cpf.strip().replace(".", "").replace("-", "")
        self.telefone = self.telefone.strip()