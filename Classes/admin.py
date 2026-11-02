"""Classe Admin (herda de Usuario) - EduFix.

Administrador com NIVEL de acesso (1 operador, 2 gerente, 3 administrador geral) e
lista de permissoes. As demais classes consultam possui_permissao() para decidir
quem pode alterar chamados, patrimonio e usuarios.
"""
from __future__ import annotations

from collections import Counter
from datetime import date, datetime
from typing import Dict, Iterable, List, Optional

from usuario import Usuario

PERMISSOES_VALIDAS = ("gerenciar_usuarios", "gerenciar_chamados",
                      "gerenciar_patrimonio", "emitir_relatorios")
PERMISSOES_DO_NIVEL = {   # permissoes minimas garantidas por nivel
    1: ("gerenciar_chamados", "gerenciar_patrimonio"),
    2: ("gerenciar_chamados", "gerenciar_patrimonio", "emitir_relatorios"),
    3: PERMISSOES_VALIDAS,
    4: PERMISSOES_VALIDAS,   # o banco aceita nivel 1..5; do 3 em diante tem tudo
    5: PERMISSOES_VALIDAS,
}
PERMISSAO_TOTAL = "admin"    # valor padrao da coluna admin.permissoes = todas as permissoes
ACOES_USUARIO = ("desativar", "reativar", "redefinir_senha", "atualizar_perfil")


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
        permissoes: str = "",
        ativo: bool = True,
        data_cadastro: Optional[date] = None,
        ultimo_login: Optional[date] = None,
    ):
        super().__init__(id_usuario, nome, senha, email, telefone, cpf, data_nascimento,
                         ativo, data_cadastro, ultimo_login)
        if nivel_acesso not in PERMISSOES_DO_NIVEL:
            raise ValueError("nivel_acesso deve estar entre 1 e 5.")
        self.nivel_acesso = nivel_acesso
        self.permissoes = self._normalizar_permissoes(permissoes)

    @staticmethod
    def _normalizar_permissoes(texto: str) -> str:
        itens = sorted({p.strip().lower() for p in (texto or "").split(",") if p.strip()})
        if PERMISSAO_TOTAL in itens:      # "admin" vale por todas
            return PERMISSAO_TOTAL
        invalidas = [p for p in itens if p not in PERMISSOES_VALIDAS]
        if invalidas:
            raise ValueError(f"Permissoes invalidas: {', '.join(invalidas)}.")
        return ",".join(itens)

    # ------------------------------------------------------- permissoes
    @property
    def eh_admin(self) -> bool:
        return True

    @property
    def permissoes_efetivas(self) -> frozenset:
        """Permissoes extras do cadastro + as garantidas pelo nivel."""
        if self.permissoes == PERMISSAO_TOTAL:
            return frozenset(PERMISSOES_VALIDAS)
        extras = set(filter(None, self.permissoes.split(",")))
        return frozenset(extras | set(PERMISSOES_DO_NIVEL[self.nivel_acesso]))

    def possui_permissao(self, permissao: str) -> bool:
        return self.ativo and permissao in self.permissoes_efetivas

    def _exigir(self, permissao: str) -> None:
        if not self.ativo:
            raise PermissionError("Administrador inativo.")
        if not self.possui_permissao(permissao):
            raise PermissionError(f"Permissao necessaria: {permissao} (nivel {self.nivel_acesso}).")

    # ------------------------------------------------------- metodos UML
    def gerenciarUsuarios(
        self, acao: str, alvo: Usuario, nova_senha: Optional[str] = None, **dados
    ) -> str:
        """Gerencia outro usuario. Acoes: desativar, reativar, redefinir_senha (exige
        nova_senha) e atualizar_perfil (**dados = nome/email/telefone/cpf/data_nascimento).
        Regras: precisa de 'gerenciar_usuarios'; ninguem gerencia a si proprio
        (evita se trancar fora); um admin so age sobre admin de nivel MENOR;
        desativar so e feito se o alvo nao tiver chamado em andamento."""
        self._exigir("gerenciar_usuarios")
        if acao not in ACOES_USUARIO:
            raise ValueError(f"Acao invalida. Use: {', '.join(ACOES_USUARIO)}.")
        if alvo is self:
            raise PermissionError("Voce nao pode executar esta acao sobre a sua propria conta.")
        if isinstance(alvo, Admin) and alvo.nivel_acesso >= self.nivel_acesso:
            raise PermissionError("So e possivel gerenciar administradores de nivel inferior.")

        if acao == "desativar":
            if not alvo.ativo:
                return f"{alvo.nome} ja estava inativo."
            ativos_abertos = [c for c in alvo.chamados if c.ativo]
            if ativos_abertos:
                ids = ", ".join(f"#{c.id_chamado}" for c in ativos_abertos)
                raise RuntimeError(f"Usuario tem chamados em andamento ({ids}); encerre-os antes.")
            alvo.ativo = False
            return f"{alvo.nome} desativado."
        if acao == "reativar":
            if alvo.ativo:
                return f"{alvo.nome} ja estava ativo."
            alvo.ativo = True
            return f"{alvo.nome} reativado."
        if acao == "redefinir_senha":
            if not nova_senha:
                raise ValueError("Informe nova_senha.")
            self._validar_politica_senha(nova_senha)
            alvo.senha = self._gerar_hash(nova_senha)
            return f"Senha de {alvo.nome} redefinida."
        # atualizar_perfil
        campos = {k: v for k, v in dados.items()
                  if k in ("nome", "email", "telefone", "cpf", "data_nascimento")}
        if not campos or len(campos) != len(dados):
            raise ValueError("Informe campos validos: nome, email, telefone, cpf, data_nascimento.")
        mudou = alvo.atualizarPerfil(**campos)
        return (f"Perfil de {alvo.nome} atualizado ({', '.join(mudou)})."
                if mudou else "Nada a alterar.")

    def emitirRelatorioOperacional(
        self,
        chamados: Iterable,
        inicio: Optional[datetime] = None,
        fim: Optional[datetime] = None,
        agora: Optional[datetime] = None,
        taxa_hora: float = 0.0,
        top: int = 3,
    ) -> dict:
        """Relatorio do periodo [inicio, fim] sobre os chamados informados: totais por
        status/prioridade/setor/categoria, SLA, tempo medio de resolucao, custo das
        manutencoes (com mao de obra se taxa_hora), bens com mais chamados e uma lista
        de alertas. Devolve um dict (use formatar_relatorio() para texto)."""
        self._exigir("emitir_relatorios")
        agora = agora or datetime.now()
        lista = [c for c in chamados if c.registrado
                 and (inicio is None or c.data_abertura >= inicio)
                 and (fim is None or c.data_abertura <= fim)]
        encerrados = [c for c in lista if c.status == "concluido"]
        tempos = [c.tempo_atendimento().total_seconds() / 3600 for c in encerrados]
        ativos = [c for c in lista if c.ativo]
        estourados = [c for c in lista if (c.ativo or c.status == "concluido") and c.sla_estourado(agora)]
        manutencoes = [m for c in lista for m in c.manutencoes]
        custo = round(sum(m.calcularCustoTotal(taxa_hora) for m in manutencoes), 2)
        por_bem = Counter(c.equipamento for c in lista)
        alertas: List[str] = []
        for c in ativos:
            if c.prioridade == "critica":
                alertas.append(f"Chamado #{c.id_chamado} CRITICO em aberto ({c.equipamento.nome}).")
            if c.sla_estourado(agora):
                alertas.append(f"Chamado #{c.id_chamado} com SLA estourado ({c.prazo_sla_horas}h).")
        for eq, n in por_bem.items():
            if n >= 3:
                alertas.append(f"{eq.nome} acumulou {n} chamados no periodo: avaliar substituicao.")
        return {
            "emitido_por": self.nome, "emitido_em": agora,
            "periodo": (inicio, fim),
            "total_chamados": len(lista),
            "por_status": dict(Counter(c.status for c in lista)),
            "por_prioridade": dict(Counter(c.prioridade for c in lista)),
            "por_setor": dict(Counter(c.equipamento.setor.nome for c in lista)),
            "por_categoria": dict(Counter(c.equipamento.categoria for c in lista)),
            "ativos": len(ativos),
            "tempo_medio_resolucao_h": round(sum(tempos) / len(tempos), 2) if tempos else None,
            "taxa_resolucao": round(len(encerrados) / len(lista), 3) if lista else 0.0,
            "sla_estourados": len(estourados),
            "sla_cumprido_pct": round(100 * (1 - len(estourados) / len(lista)), 1) if lista else 100.0,
            "manutencoes": len(manutencoes),
            "custo_manutencao": custo,
            "bens_mais_chamados": [(eq.nome, n) for eq, n in por_bem.most_common(top)],
            "alertas": alertas,
        }

    @staticmethod
    def formatar_relatorio(rel: Dict) -> str:
        linhas = [f"RELATORIO OPERACIONAL - emitido por {rel['emitido_por']} "
                  f"em {rel['emitido_em']:%d/%m/%Y %H:%M}",
                  f"Chamados: {rel['total_chamados']} (ativos: {rel['ativos']}) | "
                  f"resolucao: {rel['taxa_resolucao']*100:.0f}% | "
                  f"tempo medio: {rel['tempo_medio_resolucao_h']} h",
                  f"SLA cumprido: {rel['sla_cumprido_pct']}% | custo de manutencao: "
                  f"R$ {rel['custo_manutencao']:.2f} ({rel['manutencoes']} manutencoes)",
                  f"Por status: {rel['por_status']}", f"Por prioridade: {rel['por_prioridade']}",
                  f"Por setor: {rel['por_setor']}", f"Por categoria: {rel['por_categoria']}",
                  f"Bens com mais chamados: {rel['bens_mais_chamados']}"]
        linhas += [f"ALERTA: {a}" for a in rel["alertas"]]
        return "\n".join(linhas)

    def to_dict(self) -> dict:
        d = super().to_dict()
        d.update(nivel_acesso=self.nivel_acesso, permissoes=sorted(self.permissoes_efetivas))
        return d
