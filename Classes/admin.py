from usuario import Usuario
from chamado import Chamado
from datetime import date
from typing import Optional
from equipamento import Equipamento
from manutencao import Manutencao
from historico_status_chamado import HistoricoStatusChamado


class Admin(Usuario):
    def __init__(
        self,
        id_usuario: int,
        nome: str,
        senha: str,
        email: str,
        telefone: str,
        cpf: str,
        data_nascimento: date,
        nivel_acesso: int = 1,
        permissoes: str = "admin",
        ativo: bool = True,
        data_cadastro: Optional[date] = None,
        ultimo_login: Optional[date] = None,
    ):
        super().__init__(
            id_usuario, nome, senha, email, telefone,
            cpf, data_nascimento, ativo, data_cadastro, ultimo_login
        )
        self.nivel_acesso = nivel_acesso
        self.permissoes = permissoes
 
    def gerenciarUsuarios(self, lista_usuarios: list, acao: str, usuario: "Usuario") -> str:
        """Adiciona, remove ou atualiza um usuário na lista."""
        if acao == "adicionar":
            lista_usuarios.append(usuario)
            return f"Usuário {usuario.nome} adicionado."
        elif acao == "remover":
            lista_usuarios = [u for u in lista_usuarios if u.id_usuario != usuario.id_usuario]
            return f"Usuário {usuario.nome} removido."
        return "Ação inválida."
 
    def registrarEquipamento(self, lista_equipamentos: list, equipamento: "Equipamento") -> str:
        """Adiciona um novo equipamento ao inventário."""
        lista_equipamentos.append(equipamento)
        return f"Equipamento '{equipamento.nome}' registrado com sucesso."
 
    def atualizarEquipamento(self, equipamento: "Equipamento", **kwargs) -> str:
        """Atualiza atributos de um equipamento existente."""
        for chave, valor in kwargs.items():
            if hasattr(equipamento, chave):
                setattr(equipamento, chave, valor)
        return f"Equipamento '{equipamento.nome}' atualizado."
 
    def alterarStatusChamado(self, chamado: "Chamado", novo_status: str) -> str:
        """Altera o status de um chamado."""
        chamado.status = novo_status
        return f"Status do chamado #{chamado.id_chamado} alterado para '{novo_status}'."
 
    def atribuirManutencao(self, chamado: "Chamado", tecnico: str, descricao: str) -> "Manutencao":
        """Cria e retorna um objeto Manutencao para o chamado informado."""
        manutencao = Manutencao(
            id_manutencao=None,
            id_chamado=chamado.id_chamado,
            id_equipamento=chamado.id_equipamento,
            tecnico_responsavel=tecnico,
            descricao_servico=descricao,
        )
        return manutencao
 
    def registrarIntervencao(self, manutencao: "Manutencao", descricao: str) -> str:
        """Registra uma intervenção adicional em uma manutenção."""
        manutencao.descricao_servico += f" | Intervenção: {descricao}"
        return "Intervenção registrada."
 
    def emitirRelatorioOperacional(self, lista_chamados: list) -> str:
        """Gera um relatório resumido de todos os chamados."""
        total = len(lista_chamados)
        abertos = sum(1 for c in lista_chamados if c.status == "aberto")
        fechados = sum(1 for c in lista_chamados if c.status == "fechado")
        return (
            f"=== Relatório Operacional ===\n"
            f"Total de chamados: {total}\n"
            f"Abertos: {abertos}\n"
            f"Fechados: {fechados}"
        )
 
    def consultarInventario(self, lista_equipamentos: list) -> str:
        """Lista todos os equipamentos do inventário."""
        if not lista_equipamentos:
            return "Nenhum equipamento cadastrado."
        return "\n".join([e.exibirInfo() for e in lista_equipamentos])
 
    def finalizarChamado(self, chamado: "Chamado") -> str:
        """Finaliza um chamado, encerrando-o com data de fechamento."""
        chamado.status = "fechado"
        chamado.data_fechamento = date.today()
        return f"Chamado #{chamado.id_chamado} finalizado em {chamado.data_fechamento}."