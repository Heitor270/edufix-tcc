"""Classe Usuario - EduFix (sistema de patrimonio escolar).

Regras espelham o sistema real:
  * senha com hash pbkdf2:sha256 (formato compativel com o werkzeug do Flask);
    senha antiga em texto puro e aceita uma vez e migrada para hash no login;
  * politica de senha igual a do frontend (validarSenha);
  * nome sem espacos sobrando e e-mail minusculo (triggers trg_usuario_normaliza_*).
"""
from __future__ import annotations

import hashlib
import hmac
import re
import secrets
import string
from datetime import date, datetime
from typing import Dict, Optional, Tuple, TYPE_CHECKING

if TYPE_CHECKING:  # evita import circular
    from chamado import Chamado


class Usuario:
    ITERACOES_HASH = 600_000
    ESPECIAIS_SENHA = '!@#$%^&*()-_,.?":{}|<>'
    _EMAIL_RE = re.compile(r"^[^\s@]+@[^\s@]+\.[^\s@]+$")

    # ------------------------------------------------------------------ init
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
        self.nome = self._validar_nome(nome)
        self.email = self._validar_email(email)
        self.telefone = self._validar_telefone(telefone)
        self.cpf = self._validar_cpf(cpf)
        self.data_nascimento = self._validar_nascimento(data_nascimento)
        self.ativo = bool(ativo)
        self.data_cadastro = data_cadastro or date.today()
        self.ultimo_login = ultimo_login
        if senha.startswith("pbkdf2:"):          # veio do banco, ja e hash
            self.senha = senha
        else:
            self._validar_politica_senha(senha)
            self.senha = self._gerar_hash(senha)
        self._chamados: list = []                 # lado "0..N" da associacao

    # ------------------------------------------------- validacoes (estaticas)
    @staticmethod
    def _validar_nome(nome: str) -> str:
        nome = " ".join((nome or "").split())
        if len(nome) < 3:
            raise ValueError("Nome deve ter pelo menos 3 caracteres.")
        return nome

    @classmethod
    def _validar_email(cls, email: str) -> str:
        email = (email or "").strip().lower()
        if not cls._EMAIL_RE.match(email):
            raise ValueError("E-mail invalido.")
        return email

    @staticmethod
    def _validar_telefone(telefone: str) -> str:
        digitos = re.sub(r"\D", "", telefone or "")
        if len(digitos) not in (10, 11):
            raise ValueError("Telefone deve ter 10 ou 11 digitos (com DDD).")
        return digitos

    @staticmethod
    def validar_cpf(cpf: str) -> bool:
        """Algoritmo oficial dos dois digitos verificadores."""
        n = re.sub(r"\D", "", cpf or "")
        if len(n) != 11 or n == n[0] * 11:
            return False
        for tam in (9, 10):
            soma = sum(int(n[i]) * (tam + 1 - i) for i in range(tam))
            dv = (soma * 10 % 11) % 10
            if dv != int(n[tam]):
                return False
        return True

    @classmethod
    def _validar_cpf(cls, cpf: str) -> str:
        if not cls.validar_cpf(cpf):
            raise ValueError("CPF invalido.")
        return re.sub(r"\D", "", cpf)

    @staticmethod
    def _validar_nascimento(nasc: date) -> date:
        if isinstance(nasc, datetime):
            nasc = nasc.date()
        if nasc > date.today():
            raise ValueError("Data de nascimento no futuro.")
        if (date.today().year - nasc.year) > 120:
            raise ValueError("Data de nascimento invalida.")
        return nasc

    @classmethod
    def _validar_politica_senha(cls, s: str) -> None:
        faltas = []
        if len(s) < 8:
            faltas.append("minimo de 8 caracteres")
        if not any(c.isupper() for c in s):
            faltas.append("uma letra maiuscula")
        if not any(c.islower() for c in s):
            faltas.append("uma letra minuscula")
        if not any(c.isdigit() for c in s):
            faltas.append("um numero")
        if not any(c in cls.ESPECIAIS_SENHA for c in s):
            faltas.append("um caractere especial")
        if faltas:
            raise ValueError("Senha fraca. Falta: " + ", ".join(faltas) + ".")

    # ------------------------------------------------------------ hash/senha
    @classmethod
    def _gerar_hash(cls, senha: str) -> str:
        alfabeto = string.ascii_letters + string.digits
        sal = "".join(secrets.choice(alfabeto) for _ in range(16))
        h = hashlib.pbkdf2_hmac("sha256", senha.encode(), sal.encode(), cls.ITERACOES_HASH)
        return f"pbkdf2:sha256:{cls.ITERACOES_HASH}${sal}${h.hex()}"

    def _confere_senha(self, tentativa: str) -> bool:
        if not self.senha.startswith("pbkdf2:"):  # legado em texto puro
            return hmac.compare_digest(self.senha, tentativa)
        try:
            metodo, sal, esperado = self.senha.split("$")
            _, algoritmo, iteracoes = metodo.split(":")
            h = hashlib.pbkdf2_hmac(algoritmo, tentativa.encode(), sal.encode(), int(iteracoes))
        except (ValueError, TypeError):
            return False
        return hmac.compare_digest(h.hex(), esperado)

    # ----------------------------------------------------------- propriedades
    @property
    def eh_admin(self) -> bool:
        return False

    def possui_permissao(self, permissao: str) -> bool:
        return False

    @property
    def idade(self) -> int:
        hoje = date.today()
        return hoje.year - self.data_nascimento.year - (
            (hoje.month, hoje.day) < (self.data_nascimento.month, self.data_nascimento.day))

    @property
    def chamados(self) -> Tuple["Chamado", ...]:
        return tuple(self._chamados)

    def _registrar_chamado(self, chamado: "Chamado") -> None:
        if chamado not in self._chamados:
            self._chamados.append(chamado)

    # ------------------------------------------------------------- metodos UML
    def autenticar(self, senha_informada: str) -> bool:
        """Confere a senha. So autentica usuario ativo; no sucesso grava ultimo_login
        e, se a senha ainda era texto puro, migra para hash (igual ao backend)."""
        if not self.ativo or not senha_informada:
            return False
        if not self._confere_senha(senha_informada):
            return False
        if not self.senha.startswith("pbkdf2:"):
            self.senha = self._gerar_hash(senha_informada)
        self.ultimo_login = date.today()
        return True

    def alterarSenha(self, senha_atual: str, nova_senha: str,
                     confirmacao: Optional[str] = None) -> str:
        """Troca a senha. Exige a senha atual, a politica de seguranca, que a nova
        seja diferente da atual e (se informada) igual a confirmacao."""
        if not self.ativo:
            raise PermissionError("Usuario inativo nao pode alterar a senha.")
        if not self._confere_senha(senha_atual):
            raise PermissionError("Senha atual incorreta.")
        if confirmacao is not None and confirmacao != nova_senha:
            raise ValueError("A confirmacao nao confere com a nova senha.")
        if self._confere_senha(nova_senha):
            raise ValueError("A nova senha deve ser diferente da atual.")
        self._validar_politica_senha(nova_senha)
        if self.nome.lower().split()[0] in nova_senha.lower():
            raise ValueError("A senha nao pode conter o seu primeiro nome.")
        self.senha = self._gerar_hash(nova_senha)
        return "Senha alterada com sucesso."

    def atualizarPerfil(self, nome: Optional[str] = None, email: Optional[str] = None,
                        telefone: Optional[str] = None, cpf: Optional[str] = None,
                        data_nascimento: Optional[date] = None
                        ) -> Dict[str, Tuple[object, object]]:
        """Atualiza so o que foi informado. Valida TUDO antes de gravar (tudo ou nada)
        e devolve {campo: (valor_antigo, valor_novo)} apenas dos campos que mudaram."""
        if not self.ativo:
            raise PermissionError("Usuario inativo nao pode alterar o perfil.")
        candidatos = {}
        if nome is not None:
            candidatos["nome"] = self._validar_nome(nome)
        if email is not None:
            candidatos["email"] = self._validar_email(email)
        if telefone is not None:
            candidatos["telefone"] = self._validar_telefone(telefone)
        if cpf is not None:
            candidatos["cpf"] = self._validar_cpf(cpf)
        if data_nascimento is not None:
            candidatos["data_nascimento"] = self._validar_nascimento(data_nascimento)
        mudancas = {c: (getattr(self, c), v) for c, v in candidatos.items()
                    if getattr(self, c) != v}
        for campo, (_, novo) in mudancas.items():
            setattr(self, campo, novo)
        return mudancas

    # ------------------------------------------------------------------ extras
    def to_dict(self) -> dict:
        """Dados publicos (nunca devolve a senha/hash)."""
        return {"id_usuario": self.id_usuario, "nome": self.nome, "email": self.email,
                "telefone": self.telefone, "ativo": self.ativo,
                "data_cadastro": self.data_cadastro.isoformat(),
                "ultimo_login": self.ultimo_login.isoformat() if self.ultimo_login else None,
                "admin": self.eh_admin}

    def __repr__(self) -> str:
        return f"<{type(self).__name__} #{self.id_usuario} {self.nome!r} ativo={self.ativo}>"
