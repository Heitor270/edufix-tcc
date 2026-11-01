import os
import re
import sys
from contextlib import contextmanager
from datetime import date, datetime, timedelta
from decimal import Decimal

from dotenv import load_dotenv, dotenv_values
from flask import Flask, request, jsonify, send_from_directory
from flask_cors import CORS
from werkzeug.exceptions import HTTPException
from werkzeug.security import generate_password_hash, check_password_hash
import mysql.connector

import consultas

# ─── DE ONDE VEM A SENHA DO MYSQL ──────────
# Ordem de prioridade (a primeira que existir ganha):
#   1. senha digitada no terminal quando o app pergunta ao subir  (não precisa de arquivo)
#   2. variável de ambiente DB_PASSWORD  ou  Backend/.env  (também lê .env.txt, que o Windows
#      cria sem querer quando as extensões estão ocultas)
#   3. Backend/config_local.py  (arquivo Python comum; copie o config_local.exemplo.py)
# Nenhum desses arquivos vai pro Git — cada computador tem o seu.
_PASTA = os.path.dirname(os.path.abspath(__file__))
# procura o .env na pasta do Backend, na raiz do projeto e na pasta onde o terminal foi aberto
_RAIZ = os.path.dirname(_PASTA)
_ARQUIVOS_ENV = []
for _dir in (_PASTA, _RAIZ, os.getcwd()):
    for _nome in ('.env', '.env.txt', 'env', 'env.txt'):
        _c = os.path.join(_dir, _nome)
        if _c not in _ARQUIVOS_ENV:
            _ARQUIVOS_ENV.append(_c)
_ENV_ENCONTRADO = [a for a in _ARQUIVOS_ENV if os.path.isfile(a)]
for _arq in _ENV_ENCONTRADO:
    load_dotenv(_arq)          # não sobrescreve variáveis que já existem

try:
    import config_local as _cfg_local   # opcional
except ImportError:
    _cfg_local = None

app = Flask(__name__)
CORS(app)

# ─── CONFIGURAÇÃO ──────────────────────────

_BASE = os.path.dirname(os.path.abspath(__file__))
FRONTEND_DIR = os.path.join(os.path.dirname(_BASE), 'Frontend')

# Valores aceitos (iguais aos ENUMs do banco / selects do frontend)
STATUS_CHAMADO = {'aberto', 'em_analise', 'em_execucao', 'concluido', 'cancelado'}
PRIORIDADES = {'baixa', 'media', 'alta', 'critica'}
STATUS_EQUIPAMENTO = {'disponivel', 'em_uso', 'em_manutencao', 'inativo'}
CONSERVACAO = {'otimo', 'bom', 'regular', 'ruim', 'inutilizavel'}

EXPOR_ERROS = os.getenv('FLASK_DEBUG', '1') == '1'  # mostra o detalhe técnico do erro (só em dev)


# Nomes alternativos aceitos (cada pessoa escreve o .env de um jeito)
_ALIASES = {
    'DB_HOST': ['DB_HOST', 'MYSQL_HOST', 'DATABASE_HOST', 'HOST'],
    'DB_PORT': ['DB_PORT', 'MYSQL_PORT', 'DATABASE_PORT', 'PORTA'],
    'DB_USER': ['DB_USER', 'DB_USERNAME', 'MYSQL_USER', 'DATABASE_USER', 'USUARIO', 'USER'],
    'DB_PASSWORD': ['DB_PASSWORD', 'DB_PASS', 'DB_SENHA', 'DB_PWD', 'MYSQL_PASSWORD', 'MYSQL_PWD',
                    'MYSQL_PASS', 'DATABASE_PASSWORD', 'PASSWORD', 'PASS', 'SENHA'],
    'DB_NAME': ['DB_NAME', 'DB_DATABASE', 'MYSQL_DATABASE', 'DATABASE_NAME', 'DATABASE', 'BANCO'],
}

# Lê os arquivos .env direto (ignora maiúsculas/minúsculas e espaços ao redor)
_LIDO_DOS_ARQUIVOS = {}
for _arq in _ENV_ENCONTRADO:
    try:
        for _k, _v in (dotenv_values(_arq) or {}).items():
            if _k and _v not in (None, ''):
                _LIDO_DOS_ARQUIVOS.setdefault(_k.strip().upper(), str(_v).strip())
    except Exception:
        pass


def _valor_config(nome, padrao):
    """Variável de ambiente > .env (nomes alternativos) > config_local.py > padrão."""
    for alias in _ALIASES.get(nome, [nome]):
        if os.getenv(alias) not in (None, ''):
            return os.getenv(alias)
        if alias in _LIDO_DOS_ARQUIVOS:
            return _LIDO_DOS_ARQUIVOS[alias]
    if _cfg_local is not None and getattr(_cfg_local, nome, '') not in (None, ''):
        return getattr(_cfg_local, nome)
    return padrao


def _senhas_candidatas():
    """Todas as senhas encontradas, na ordem: variável de ambiente > .env > config_local.py.
    Se uma estiver errada, o app tenta a próxima (por isso funciona 'com .env ou sem .env')."""
    achadas = []
    for alias in _ALIASES['DB_PASSWORD']:
        for v in (os.getenv(alias), _LIDO_DOS_ARQUIVOS.get(alias)):
            if v not in (None, '') and str(v) not in achadas:
                achadas.append(str(v))
    if _cfg_local is not None:
        v = getattr(_cfg_local, 'DB_PASSWORD', '')
        if v not in (None, '') and str(v) not in achadas:
            achadas.append(str(v))
    return achadas or ['']


_SENHA_QUE_FUNCIONOU = None


def config_banco(senha=None):
    if senha is None:
        senha = _SENHA_QUE_FUNCIONOU if _SENHA_QUE_FUNCIONOU is not None else _senhas_candidatas()[0]
    return {
        'host': _valor_config('DB_HOST', 'localhost'),
        'port': int(_valor_config('DB_PORT', 3306)),
        'user': _valor_config('DB_USER', 'root'),
        'password': senha,
        'database': _valor_config('DB_NAME', 'inventario_escolar'),
    }


def conectar():
    global _SENHA_QUE_FUNCIONOU
    if _SENHA_QUE_FUNCIONOU is not None:
        return mysql.connector.connect(connection_timeout=10, **config_banco())
    ultimo_erro = None
    for senha in _senhas_candidatas():
        try:
            conn = mysql.connector.connect(connection_timeout=10, **config_banco(senha))
            _SENHA_QUE_FUNCIONOU = senha
            return conn
        except mysql.connector.Error as e:
            if e.errno != 1045:        # só tenta a próxima senha se foi "acesso negado"
                raise
            ultimo_erro = e
    raise ultimo_erro


# ─── HELPERS DE BANCO ──────────────────────

def _limpar(valor):
    """Converte tipos que o JSON não entende (Decimal, datas, timedelta)."""
    if isinstance(valor, dict):
        return {k: _limpar(v) for k, v in valor.items()}
    if isinstance(valor, (list, tuple)):
        return [_limpar(v) for v in valor]
    if isinstance(valor, (datetime, date)):
        return valor.isoformat()          # '2026-09-28' ou '2026-09-28T14:30:00'
    if isinstance(valor, Decimal):
        return float(valor)
    if isinstance(valor, timedelta):
        return str(valor)
    if isinstance(valor, (bytes, bytearray)):
        return valor.decode('utf-8', errors='replace')
    return valor


@contextmanager
def cursor_db(commit=False):
    """Abre conexão + cursor e SEMPRE fecha, mesmo se der erro no meio."""
    conn = conectar()
    try:
        cur = conn.cursor(dictionary=True)
        try:
            yield cur
            if commit:
                conn.commit()
        except Exception:
            conn.rollback()
            raise
        finally:
            cur.close()
    finally:
        conn.close()


def consultar(sql, params=(), um=False):
    with cursor_db() as cur:
        cur.execute(sql, params)
        resultado = cur.fetchone() if um else cur.fetchall()
    return _limpar(resultado)


def executar(sql, params=()):
    """INSERT/UPDATE/DELETE com commit. Retorna (linhas_afetadas, ultimo_id)."""
    with cursor_db(commit=True) as cur:
        cur.execute(sql, params)
        return cur.rowcount, cur.lastrowid


def chamar_procedure(nome, args, commit=False):
    """CALL de procedure. commit=True para as que alteram dados."""
    with cursor_db(commit=commit) as cur:
        cur.callproc(nome, args)
        linhas = []
        for r in cur.stored_results():
            colunas = r.column_names
            linhas = [
                linha if isinstance(linha, dict) else dict(zip(colunas, linha))
                for linha in r.fetchall()
            ]
    return _limpar(linhas)


# ─── HELPERS DE REQUISIÇÃO / ERROS ─────────

class ErroRequisicao(Exception):
    def __init__(self, mensagem, status=400):
        super().__init__(mensagem)
        self.mensagem = mensagem
        self.status = status


def ok(mensagem, **extra):
    return jsonify({'sucesso': True, 'mensagem': mensagem, **extra})


def corpo(*obrigatorios):
    """Lê o JSON do body e garante que os campos obrigatórios vieram preenchidos."""
    dados = request.get_json(silent=True)
    if not isinstance(dados, dict):
        raise ErroRequisicao('Corpo da requisição inválido (era esperado JSON).')
    faltando = [c for c in obrigatorios if dados.get(c) in (None, '')]
    if faltando:
        raise ErroRequisicao('Campos obrigatórios ausentes: ' + ', '.join(faltando))
    return dados


# Mesma regra do front: algo antes do @ + @ + domínio com ponto + terminação de 2+ letras
# (aceita pessoal, institucional e de prefeitura: .com, .com.br, .gov.br, .edu.br...)
_REGEX_EMAIL = re.compile(
    r'^[A-Za-z0-9](?:[A-Za-z0-9._%+\-]*[A-Za-z0-9])?@(?:[A-Za-z0-9](?:[A-Za-z0-9\-]*[A-Za-z0-9])?\.)+[A-Za-z]{2,}$')


def validar_email(email):
    email = str(email).strip()
    if len(email) > 100 or '..' in email or not _REGEX_EMAIL.match(email):
        raise ErroRequisicao('E-mail inválido. Use o formato nome@dominio.com.')
    return email


def exigir_admin():
    """Só administrador passa. O front manda o id de quem está logado no cabeçalho X-Usuario-Id
    e aqui o perfil é conferido no banco (não dá para confiar só no que o navegador diz ser)."""
    bruto = request.headers.get('X-Usuario-Id', '').strip()
    if not bruto.isdigit():
        raise ErroRequisicao('Faça login para continuar.', 401)
    quem = consultar('SELECT ativo, fn_usuario_eh_admin(id_usuario) AS eh_admin '
                     'FROM usuario WHERE id_usuario = %s', (int(bruto),), um=True)
    if not quem or not quem['ativo']:
        raise ErroRequisicao('Faça login para continuar.', 401)
    if not quem['eh_admin']:
        raise ErroRequisicao('Acesso restrito a administradores.', 403)


def exigir_em(valor, permitidos, campo):
    if valor not in permitidos:
        raise ErroRequisicao(f"Valor inválido para '{campo}': {valor}")


@app.errorhandler(ErroRequisicao)
def tratar_erro_requisicao(e):
    return jsonify({'sucesso': False, 'mensagem': e.mensagem}), e.status


@app.errorhandler(HTTPException)
def tratar_http(e):
    # 404, 405, 415... também saem em JSON, para o frontend nunca receber HTML
    return jsonify({'sucesso': False, 'mensagem': e.description}), e.code


@app.errorhandler(mysql.connector.IntegrityError)
def tratar_integridade(e):
    if e.errno == 1451:   # tentou apagar algo que outra tabela usa
        return jsonify({'sucesso': False,
                        'mensagem': 'Não é possível remover: existem registros vinculados (chamados/manutenções).'}), 409
    if e.errno == 1452:   # chave estrangeira inexistente
        return jsonify({'sucesso': False,
                        'mensagem': 'Referência inválida: usuário ou equipamento não existe.'}), 400
    return jsonify({'sucesso': False, 'mensagem': 'Registro duplicado ou dados inválidos.'}), 409


@app.errorhandler(mysql.connector.DatabaseError)
def tratar_erro_do_banco(e):
    # Regras de negócio das procedures usam SIGNAL SQLSTATE '45xxx' (ex.: 45404, 45409):
    # os 3 últimos dígitos viram o status HTTP e a mensagem escrita no banco vai para a tela.
    estado = str(getattr(e, 'sqlstate', '') or '')
    if estado.startswith('45') and len(estado) == 5 and estado[2:].isdigit():
        return jsonify({'sucesso': False, 'mensagem': e.msg}), int(estado[2:])
    if e.errno in (1305, 1146, 1356):   # procedure/function/view não existe
        return jsonify({'sucesso': False,
                        'mensagem': 'Falta um objeto do banco de dados. Execute os scripts SQL '
                                    '(functions, procedures, triggers e views) no MySQL.'}), 500
    return tratar_erro_geral(e)


@app.errorhandler(Exception)
def tratar_erro_geral(e):
    app.logger.exception('Erro não tratado: %s', e)
    if isinstance(e, mysql.connector.Error):
        msg = 'Não foi possível acessar o banco de dados.'
        if isinstance(e, mysql.connector.errors.ProgrammingError) and e.errno == 1045:
            msg += ' Usuário/senha do MySQL incorretos (confira o Backend/.env).'
        elif isinstance(e, mysql.connector.errors.DatabaseError) and getattr(e, 'errno', None) == 1049:
            msg += ' O banco "inventario_escolar" não existe nesse computador.'
    else:
        msg = 'Erro interno do servidor.'
    if EXPOR_ERROS:
        msg += f' Detalhe: {e}'
    return jsonify({'sucesso': False, 'mensagem': msg}), 500


# ─── SENHAS ────────────────────────────────

_PREFIXOS_HASH = ('pbkdf2:', 'scrypt:')


def gerar_hash(senha):
    return generate_password_hash(senha, method='pbkdf2:sha256')


def senha_confere(salvo, digitada):
    if not salvo:
        return False
    if salvo.startswith(_PREFIXOS_HASH):
        return check_password_hash(salvo, digitada)
    return salvo == digitada  # usuário antigo com senha em texto puro (migrada no próximo login)


_banco_preparado = False


def garantir_banco():
    """Ajusta o schema na subida: garante que usuario.senha cabe um hash (VARCHAR 255)."""
    global _banco_preparado
    if _banco_preparado:
        return
    try:
        with cursor_db(commit=True) as cur:
            cur.execute("""
                SELECT DATA_TYPE AS tipo, CHARACTER_MAXIMUM_LENGTH AS tam, IS_NULLABLE AS nulo
                FROM information_schema.COLUMNS
                WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'usuario' AND COLUMN_NAME = 'senha'
            """)
            col = cur.fetchone()
            if col and col['tipo'] in ('varchar', 'char') and (col['tam'] or 0) < 255:
                nulo = 'NULL' if col['nulo'] == 'YES' else 'NOT NULL'
                cur.execute(f'ALTER TABLE usuario MODIFY senha VARCHAR(255) {nulo}')
                app.logger.info('Coluna usuario.senha ampliada para VARCHAR(255).')

        _banco_preparado = True
    except Exception as e:
        app.logger.warning('Não foi possível preparar o banco agora: %s', e)


# ─── FRONTEND ──────────────────────────────

@app.route('/')
def index():
    return send_from_directory(FRONTEND_DIR, 'index.html')


@app.route('/health')
def health():
    """Abra /health no navegador para testar o servidor e a conexão com o MySQL."""
    cfg = config_banco()
    info = {'host': cfg['host'], 'port': cfg['port'], 'database': cfg['database'], 'user': cfg['user']}
    try:
        consultar('SELECT 1 AS ok', um=True)
        return jsonify({'ok': True, 'banco': info})
    except Exception as e:
        app.logger.error('Falha no /health: %s', e)
        return jsonify({'ok': False, 'banco': info, 'erro': str(e)}), 500


@app.route('/<path:filename>')
def frontend(filename):
    return send_from_directory(FRONTEND_DIR, filename)


# ─── USUARIO ───────────────────────────────

@app.route('/login', methods=['POST'])
def login():
    dados = corpo('email', 'senha')
    garantir_banco()

    usuario = consultar('SELECT * FROM usuario WHERE email = %s', (dados['email'],), um=True)
    if not usuario or not senha_confere(usuario.get('senha'), dados['senha']):
        return jsonify({'sucesso': False, 'mensagem': 'Email ou senha inválidos'}), 401

    if usuario.get('ativo') == 0:
        return jsonify({'sucesso': False, 'mensagem': 'Usuário inativo. Procure um administrador.'}), 403

    try:
        executar('UPDATE usuario SET ultimo_login = NOW() WHERE id_usuario = %s', (usuario['id_usuario'],))
        usuario['ultimo_login'] = datetime.now().isoformat(timespec='seconds')
    except Exception as e:
        app.logger.warning('Não foi possível registrar o último login: %s', e)

    if not usuario['senha'].startswith(_PREFIXOS_HASH):
        try:
            executar('UPDATE usuario SET senha = %s WHERE id_usuario = %s',
                     (gerar_hash(dados['senha']), usuario['id_usuario']))
        except Exception as e:
            app.logger.warning('Não foi possível migrar a senha do usuário %s: %s',
                               usuario['id_usuario'], e)

    usuario.pop('senha', None)      # nunca devolve a senha para o navegador
    return jsonify({'sucesso': True, 'usuario': usuario})


@app.route('/cadastrar', methods=['POST'])
def cadastrar():
    dados = corpo('nome', 'email', 'senha', 'cpf', 'data_nascimento')
    dados['email'] = validar_email(dados['email'])
    garantir_banco()
    try:
        executar("""
            INSERT INTO usuario (nome, email, senha, cpf, telefone, data_nascimento)
            VALUES (%s, %s, %s, %s, %s, %s)
        """, (dados['nome'], dados['email'], gerar_hash(dados['senha']),
              dados['cpf'], dados.get('telefone', ''), dados['data_nascimento']))
    except mysql.connector.IntegrityError as e:
        if e.errno == 1062:
            return jsonify({'sucesso': False, 'mensagem': 'Email ou CPF já cadastrado!'}), 409
        raise
    return ok('Usuário cadastrado!')


# ─── EQUIPAMENTO ───────────────────────────

@app.route('/equipamentos', methods=['GET'])
def listar_equipamentos():
    """Filtros opcionais: ?categoria=&status=&busca= (nome ou nº de patrimônio)."""
    where, params = [], []
    categoria = request.args.get('categoria', '').strip()
    status = request.args.get('status', '').strip()
    busca = request.args.get('busca', '').strip()
    if categoria:
        where.append('categoria = %s')
        params.append(categoria)
    if status:
        where.append('status = %s')
        params.append(status)
    if busca:
        where.append('(nome LIKE %s OR numero_patrimonio LIKE %s)')
        params += [f'%{busca}%', f'%{busca}%']
    sql = 'SELECT * FROM equipamento'
    if where:
        sql += ' WHERE ' + ' AND '.join(where)
    return jsonify(consultar(sql + ' ORDER BY nome', tuple(params)))


@app.route('/equipamentos/<int:id>', methods=['GET'])
def detalhar_equipamento(id):
    equipamento = consultar("""
        SELECT e.*,
               fn_custo_total_manutencao(e.id_equipamento)     AS custo_total_manutencao,
               fn_total_chamados_equipamento(e.id_equipamento) AS total_chamados,
               fn_verificar_disponibilidade(e.id_equipamento)  AS disponibilidade
        FROM equipamento e
        WHERE e.id_equipamento = %s
    """, (id,), um=True)
    if not equipamento:
        return jsonify({'sucesso': False, 'mensagem': 'Equipamento não encontrado'}), 404
    return jsonify(equipamento)


@app.route('/equipamentos', methods=['POST'])
def adicionar_equipamento():
    dados = corpo('nome', 'numero_patrimonio', 'data_aquisicao')
    if not re.fullmatch(r'\d+', dados['numero_patrimonio']):
        raise ErroRequisicao('Número de patrimônio deve conter só números.')
    estado = dados.get('estado_conservacao', 'bom')
    status = dados.get('status', 'disponivel')
    exigir_em(estado, CONSERVACAO, 'estado_conservacao')
    exigir_em(status, STATUS_EQUIPAMENTO, 'status')
    try:
        executar("""
            INSERT INTO equipamento (nome, descricao, estado_conservacao, localizacao,
                                     numero_patrimonio, categoria, status, data_aquisicao)
            VALUES (%s, %s, %s, %s, %s, %s, %s, %s)
        """, (dados['nome'], dados.get('descricao', ''), estado,
              dados.get('localizacao', ''), dados['numero_patrimonio'],
              dados.get('categoria', 'Outro'), status, dados['data_aquisicao']))
    except mysql.connector.IntegrityError as e:
        if e.errno == 1062:
            return jsonify({'sucesso': False, 'mensagem': 'Nº de patrimônio já cadastrado!'}), 409
        raise
    return ok('Equipamento adicionado!')


@app.route('/equipamentos/<int:id>', methods=['PUT'])
def atualizar_equipamento(id):
    dados = corpo('nome')
    estado = dados.get('estado_conservacao', 'bom')
    status = dados.get('status', 'disponivel')
    exigir_em(estado, CONSERVACAO, 'estado_conservacao')
    exigir_em(status, STATUS_EQUIPAMENTO, 'status')
    executar("""
        UPDATE equipamento SET nome=%s, descricao=%s, estado_conservacao=%s,
        localizacao=%s, categoria=%s, status=%s WHERE id_equipamento=%s
    """, (dados['nome'], dados.get('descricao', ''), estado,
          dados.get('localizacao', ''), dados.get('categoria', 'Outro'), status, id))
    return ok('Equipamento atualizado!')


@app.route('/equipamentos/<int:id>', methods=['DELETE'])
def deletar_equipamento(id):
    apagadas, _ = executar('DELETE FROM equipamento WHERE id_equipamento = %s', (id,))
    if apagadas == 0:
        return jsonify({'sucesso': False, 'mensagem': 'Equipamento não encontrado'}), 404
    return ok('Equipamento removido!')


# ─── CHAMADO ───────────────────────────────

@app.route('/chamados', methods=['GET'])
def listar_chamados():
    return jsonify(consultar('SELECT * FROM chamado ORDER BY id_chamado DESC'))


@app.route('/chamados/<int:id>', methods=['GET'])
def detalhar_chamado(id):
    chamado = consultar("""
        SELECT c.*,
               fn_tempo_resolucao_chamado(c.id_chamado) AS tempo_resolucao_dias
        FROM chamado c
        WHERE c.id_chamado = %s
    """, (id,), um=True)
    if not chamado:
        return jsonify({'sucesso': False, 'mensagem': 'Chamado não encontrado'}), 404
    return jsonify(chamado)


@app.route('/chamados', methods=['POST'])
def abrir_chamado():
    dados = corpo('id_usuario', 'prioridade', 'descricao_problema')
    exigir_em(dados['prioridade'], PRIORIDADES, 'prioridade')
    executar("""
        INSERT INTO chamado (id_usuario, id_equipamento, prioridade, descricao_problema, observacoes)
        VALUES (%s, %s, %s, %s, %s)
    """, (dados['id_usuario'], dados.get('id_equipamento'), dados['prioridade'],
          dados['descricao_problema'], dados.get('observacoes', '')))
    return ok('Chamado aberto!')


@app.route('/chamados/<int:id>', methods=['PUT'])
def editar_chamado(id):
    """Edita os dados do chamado (o status continua sendo trocado em /status, com histórico)."""
    dados = corpo('prioridade', 'descricao_problema')
    exigir_em(dados['prioridade'], PRIORIDADES, 'prioridade')
    apagadas, _ = executar("""
        UPDATE chamado SET prioridade=%s, descricao_problema=%s, observacoes=%s, id_equipamento=%s
        WHERE id_chamado=%s
    """, (dados['prioridade'], dados['descricao_problema'], dados.get('observacoes', ''),
          dados.get('id_equipamento') or None, id))
    if apagadas == 0 and not consultar('SELECT 1 AS x FROM chamado WHERE id_chamado=%s', (id,), um=True):
        raise ErroRequisicao('Chamado não encontrado', 404)
    return ok('Chamado atualizado!')


@app.route('/chamados/<int:id>/status', methods=['PUT'])
def atualizar_status_chamado(id):
    dados = corpo('status', 'id_usuario')
    exigir_em(dados['status'], STATUS_CHAMADO, 'status')

    # a procedure faz tudo numa transação: troca o status, grava o histórico e
    # (pela trigger) preenche/limpa data_fechamento. Chamado inexistente -> 404.
    chamar_procedure('sp_alterar_status_chamado',
                     [id, dados['status'], dados['id_usuario'], dados.get('observacao', '')], commit=True)
    return ok('Status atualizado!')


@app.route('/chamados/<int:id>/historico', methods=['GET'])
def historico_chamado(id):
    return jsonify(consultar("""
        SELECT h.*, u.nome AS usuario
        FROM historico_status_chamado h
        LEFT JOIN usuario u ON u.id_usuario = h.id_usuario
        WHERE h.id_chamado = %s
        ORDER BY h.data_alteracao
    """, (id,)))


@app.route('/chamados/<int:id>', methods=['DELETE'])
def deletar_chamado(id):
    apagadas = 0
    with cursor_db(commit=True) as cur:
        cur.execute('DELETE FROM historico_status_chamado WHERE id_chamado = %s', (id,))
        cur.execute('DELETE FROM chamado WHERE id_chamado = %s', (id,))
        apagadas = cur.rowcount
    if apagadas == 0:
        return jsonify({'sucesso': False, 'mensagem': 'Chamado não encontrado'}), 404
    return ok('Chamado removido!')


# ─── MANUTENCAO ────────────────────────────

SQL_MANUTENCOES = """
    SELECT m.*, e.nome AS equipamento, e.numero_patrimonio,
           c.descricao_problema, c.status AS status_chamado
    FROM manutencao m
    INNER JOIN equipamento e ON e.id_equipamento = m.id_equipamento
    INNER JOIN chamado c     ON c.id_chamado     = m.id_chamado
"""


def _numero_custo(valor):
    try:
        custo = float(valor if valor not in (None, '') else 0)
    except (TypeError, ValueError):
        raise ErroRequisicao('Custo inválido.')
    if custo < 0:
        raise ErroRequisicao('O custo não pode ser negativo.')
    return custo


def _validar_periodo(inicio, fim):
    if fim and str(fim) < str(inicio):
        raise ErroRequisicao('A data de fim não pode ser anterior à data de início.')


# O status do equipamento ('em_manutencao' <-> 'disponivel') é acertado pelas triggers
# trg_manutencao_after_insert/update/delete do banco (via sp_sincronizar_equipamento).


@app.route('/manutencoes', methods=['GET'])
def listar_manutencoes():
    """?situacao=andamento|concluida (opcional)."""
    situacao = request.args.get('situacao', '')
    sql = SQL_MANUTENCOES
    if situacao == 'andamento':
        sql += ' WHERE m.data_fim IS NULL'
    elif situacao == 'concluida':
        sql += ' WHERE m.data_fim IS NOT NULL'
    return jsonify(consultar(sql + ' ORDER BY m.data_inicio DESC, m.id_manutencao DESC'))


@app.route('/manutencoes/<int:id>', methods=['GET'])
def detalhar_manutencao(id):
    manutencao = consultar(SQL_MANUTENCOES + ' WHERE m.id_manutencao = %s', (id,), um=True)
    if not manutencao:
        raise ErroRequisicao('Manutenção não encontrada', 404)
    return jsonify(manutencao)


@app.route('/manutencoes', methods=['POST'])
def registrar_manutencao():
    dados = corpo('id_chamado', 'id_equipamento', 'data_inicio', 'tecnico_responsavel')
    custo = _numero_custo(dados.get('custo'))
    _validar_periodo(dados['data_inicio'], dados.get('data_fim'))
    with cursor_db(commit=True) as cur:
        cur.execute("""
            INSERT INTO manutencao (id_chamado, id_equipamento, data_inicio, data_fim,
                                    descricao_servico, tecnico_responsavel, custo)
            VALUES (%s, %s, %s, %s, %s, %s, %s)
        """, (dados['id_chamado'], dados['id_equipamento'], dados['data_inicio'],
              dados.get('data_fim') or None, dados.get('descricao_servico', ''),
              dados['tecnico_responsavel'], custo))
    return ok('Manutenção registrada!')


@app.route('/manutencoes/<int:id>', methods=['PUT'])
def editar_manutencao(id):
    """Edita a manutenção. Informar data_fim a conclui; limpar data_fim a reabre."""
    dados = corpo('data_inicio', 'tecnico_responsavel')
    custo = _numero_custo(dados.get('custo'))
    _validar_periodo(dados['data_inicio'], dados.get('data_fim'))
    with cursor_db(commit=True) as cur:
        cur.execute('SELECT id_equipamento FROM manutencao WHERE id_manutencao=%s', (id,))
        atual = cur.fetchone()
        if not atual:
            raise ErroRequisicao('Manutenção não encontrada', 404)
        cur.execute("""
            UPDATE manutencao SET data_inicio=%s, data_fim=%s, descricao_servico=%s,
                                  tecnico_responsavel=%s, custo=%s
            WHERE id_manutencao=%s
        """, (dados['data_inicio'], dados.get('data_fim') or None, dados.get('descricao_servico', ''),
              dados['tecnico_responsavel'], custo, id))
    return ok('Manutenção atualizada!')


@app.route('/manutencoes/<int:id>', methods=['DELETE'])
def deletar_manutencao(id):
    with cursor_db(commit=True) as cur:
        cur.execute('SELECT id_equipamento FROM manutencao WHERE id_manutencao=%s', (id,))
        atual = cur.fetchone()
        if not atual:
            raise ErroRequisicao('Manutenção não encontrada', 404)
        cur.execute('DELETE FROM manutencao WHERE id_manutencao=%s', (id,))
    return ok('Manutenção removida!')


# ─── USUÁRIOS (CRUD) ───────────────────────

CAMPOS_USUARIO = ('u.id_usuario, u.nome, u.email, u.cpf, u.telefone, u.data_nascimento, u.tipo_usuario, '
                  'u.ativo, u.data_cadastro, u.ultimo_login')


@app.route('/usuarios', methods=['GET'])
def listar_usuarios():
    """Nunca devolve a senha. ?busca= filtra por nome ou e-mail."""
    exigir_admin()
    busca = request.args.get('busca', '').strip()
    sql = f"""SELECT {CAMPOS_USUARIO},
                     fn_total_chamados_abertos(u.id_usuario) AS chamados_abertos
              FROM usuario u"""
    params = ()
    if busca:
        sql += ' WHERE u.nome LIKE %s OR u.email LIKE %s'
        params = (f'%{busca}%', f'%{busca}%')
    return jsonify(consultar(sql + ' ORDER BY u.nome', params))


@app.route('/usuarios/<int:id>', methods=['GET'])
def detalhar_usuario(id):
    exigir_admin()
    usuario = consultar(f'SELECT {CAMPOS_USUARIO} FROM usuario u WHERE u.id_usuario = %s', (id,), um=True)
    if not usuario:
        raise ErroRequisicao('Usuário não encontrado', 404)
    return jsonify(usuario)


@app.route('/usuarios/<int:id>', methods=['PUT'])
def editar_usuario(id):
    """Edita dados do usuário. 'senha' é opcional (só troca se vier preenchida)."""
    exigir_admin()
    dados = corpo('nome', 'email')
    dados['email'] = validar_email(dados['email'])
    tipo = dados.get('tipo_usuario', 'usuario')
    exigir_em(tipo, {'usuario', 'admin'}, 'tipo_usuario')
    ativo = 0 if dados.get('ativo') in (False, 0, '0', 'false') else 1
    senha = dados.get('senha') or ''
    if senha and len(senha) < 6:
        raise ErroRequisicao('A senha deve ter pelo menos 6 caracteres.')
    try:
        with cursor_db(commit=True) as cur:
            cur.execute('SELECT 1 AS x FROM usuario WHERE id_usuario=%s', (id,))
            if not cur.fetchone():
                raise ErroRequisicao('Usuário não encontrado', 404)
            cur.execute("""
                UPDATE usuario SET nome=%s, email=%s, telefone=%s, data_nascimento=%s, tipo_usuario=%s, ativo=%s
                WHERE id_usuario=%s
            """, (dados['nome'], dados['email'], dados.get('telefone', ''),
                  dados.get('data_nascimento') or None, tipo, ativo, id))
            if senha:
                cur.execute('UPDATE usuario SET senha=%s WHERE id_usuario=%s', (gerar_hash(senha), id))
            if tipo == 'admin':
                cur.execute('SELECT 1 AS x FROM admin WHERE id_admin=%s', (id,))
                if not cur.fetchone():
                    cur.execute("INSERT INTO admin (id_admin, nivel_acesso, permissoes) VALUES (%s, 1, 'admin')",
                                (id,))
            else:
                cur.execute('DELETE FROM admin WHERE id_admin=%s', (id,))
    except mysql.connector.IntegrityError as e:
        if e.errno == 1062:
            return jsonify({'sucesso': False, 'mensagem': 'Esse e-mail já está em uso.'}), 409
        raise
    return ok('Usuário atualizado!')


@app.route('/usuarios/<int:id>', methods=['DELETE'])
def deletar_usuario(id):
    exigir_admin()
    # regra de integridade dentro do banco: 404 se não existe, 409 se tem chamados/histórico
    chamar_procedure('sp_remover_usuario', [id], commit=True)
    return ok('Usuário removido!')


# ─── ADMIN ─────────────────────────────────

@app.route('/admin', methods=['POST'])
def promover_admin():
    exigir_admin()
    dados = corpo('id_usuario')
    try:
        nivel = int(dados.get('nivel_acesso', 1))
    except (TypeError, ValueError):
        nivel = 0
    if not 1 <= nivel <= 5:
        raise ErroRequisicao('O nível de acesso deve ser de 1 a 5.')
    chamar_procedure('sp_promover_admin', [dados['id_usuario'], nivel, dados.get('permissoes', 'admin')],
                     commit=True)
    return ok('Usuário promovido a admin!')


@app.route('/admin', methods=['GET'])
def listar_admins():
    exigir_admin()
    return jsonify(consultar("""
        SELECT u.id_usuario, u.nome, u.email,
               a.nivel_acesso, a.permissoes,
               fn_total_chamados_abertos(u.id_usuario) AS chamados_abertos
        FROM usuario u
        INNER JOIN admin a ON u.id_usuario = a.id_admin
    """))


# ─── RELATÓRIO (RF10) ──────────────────────

@app.route('/relatorio', methods=['GET'])
def relatorio():
    por_status = consultar('SELECT status, COUNT(*) AS total FROM chamado GROUP BY status')
    total_equipamentos = consultar('SELECT COUNT(*) AS total FROM equipamento', um=True)
    custo_total = consultar('SELECT SUM(custo) AS custo_total FROM manutencao', um=True)
    equipamentos_resumo = consultar("""
        SELECT e.id_equipamento, e.nome,
               fn_custo_total_manutencao(e.id_equipamento)     AS custo_manutencao,
               fn_total_chamados_equipamento(e.id_equipamento) AS total_chamados,
               fn_verificar_disponibilidade(e.id_equipamento)  AS disponibilidade
        FROM equipamento e
        ORDER BY fn_custo_total_manutencao(e.id_equipamento) DESC
    """)
    return jsonify({
        'chamados_por_status': por_status,
        'total_equipamentos': total_equipamentos['total'],
        'custo_total_manutencoes': custo_total['custo_total'] or 0,
        'equipamentos_resumo': equipamentos_resumo,
    })


# ─── PROCEDURES DE CONSULTAS COMPLEXAS ────

@app.route('/relatorio/equipamentos', methods=['GET'])
def relatorio_equipamentos():
    return jsonify(chamar_procedure('sp_resumo_equipamentos', [request.args.get('categoria')]))


@app.route('/relatorio/chamados', methods=['GET'])
def relatorio_chamados():
    return jsonify(chamar_procedure('sp_chamados_detalhados', [request.args.get('status')]))


@app.route('/relatorio/usuarios', methods=['GET'])
def relatorio_usuarios():
    exigir_admin()          # lista todas as pessoas do sistema: só administrador
    return jsonify(chamar_procedure('sp_desempenho_usuarios', []))


# ─── CATÁLOGO DE CONSULTAS SQL ─────────────

def _valor_parametro(p, bruto):
    """Valida e converte o valor de um parâmetro conforme o tipo declarado no catálogo."""
    if bruto is None or str(bruto).strip() == '':
        bruto = p['padrao']
    tipo = p['tipo']
    if tipo == 'numero':
        try:
            n = int(bruto)
        except (TypeError, ValueError):
            raise ErroRequisicao(f"O campo '{p['rotulo']}' precisa ser um número inteiro.")
        if not 0 <= n <= 1000:
            raise ErroRequisicao(f"O campo '{p['rotulo']}' deve estar entre 0 e 1000.")
        return n
    if tipo == 'data':
        try:
            return datetime.strptime(str(bruto), '%Y-%m-%d').strftime('%Y-%m-%d')
        except ValueError:
            raise ErroRequisicao(f"Data inválida em '{p['rotulo']}' (use AAAA-MM-DD).")
    if tipo == 'selecao':
        if bruto not in p['opcoes']:
            raise ErroRequisicao(f"Valor inválido para '{p['rotulo']}'.")
        return bruto
    # texto livre: os curingas do LIKE (% _ \\) são tratados dentro da procedure sp_buscar_equipamento
    return str(bruto).strip()[:100]


# o site não precisa saber qual objeto do banco responde cada consulta
_CAMPOS_INTERNOS = ('objeto', 'ordem')


@app.route('/consultas', methods=['GET'])
def catalogo_consultas():
    return jsonify({
        'niveis': [{'id': k, 'titulo': v} for k, v in consultas.NIVEIS.items()],  # lista = ordem garantida
        'consultas': [{k: v for k, v in c.items() if k not in _CAMPOS_INTERNOS} for c in consultas.CONSULTAS],
    })


@app.route('/consultas/<id>', methods=['GET'])
def executar_consulta(id):
    c = consultas.POR_ID.get(id.upper())
    if not c:
        raise ErroRequisicao('Consulta não encontrada', 404)
    valores = {p['nome']: _valor_parametro(p, request.args.get(p['nome'])) for p in c['parametros']}
    obj = c['objeto']
    if obj['tipo'] == 'view':
        # consulta sem parâmetro = VIEW (views.sql). O ORDER BY explícito garante a ordem em qualquer versão
        linhas = consultar(f"SELECT * FROM `{obj['nome']}` ORDER BY {c['ordem']}")
    else:
        # consulta com parâmetro = PROCEDURE (procedures.sql). Vazio vira NULL (= "todos"); 0 continua 0
        args = [valores[p['nome']] if valores[p['nome']] != '' else None for p in c['parametros']]
        linhas = chamar_procedure(obj['nome'], args)
    colunas = list(linhas[0].keys()) if linhas else []
    return jsonify({'id': c['id'], 'colunas': colunas, 'linhas': linhas, 'total': len(linhas)})


# ─── INICIALIZAÇÃO ─────────────────────────

garantir_banco()   # tenta já na subida; se o MySQL ainda não estiver de pé, tenta de novo no 1º acesso

_OBJETOS_ESPERADOS = {
    'VIEW': [c['objeto']['nome'] for c in consultas.CONSULTAS if c['objeto']['tipo'] == 'view'],
    'PROCEDURE': sorted({c['objeto']['nome'] for c in consultas.CONSULTAS if c['objeto']['tipo'] == 'procedure'}
                        | {'sp_alterar_status_chamado', 'sp_sincronizar_equipamento',
                           'sp_promover_admin', 'sp_remover_usuario',
                           'sp_transferir_equipamento', 'sp_historico_equipamento'}),
    'FUNCTION': ['fn_chamados_ativos_equipamento', 'fn_equipamento_inativo', 'fn_usuario_eh_admin', 'fn_manutencoes_em_andamento', 'fn_total_vinculos_usuario',
                 'fn_custo_total_chamado', 'fn_custo_total_manutencao', 'fn_verificar_disponibilidade',
                 'fn_total_chamados_equipamento'],
}


def _objetos_faltando():
    """Confere se os scripts SQL (functions, views, procedures, triggers) foram executados."""
    faltam = []
    with cursor_db() as cur:
        cur.execute('SELECT ROUTINE_NAME AS n, ROUTINE_TYPE AS t FROM information_schema.ROUTINES '
                    'WHERE ROUTINE_SCHEMA = DATABASE()')
        existentes = {(r['t'], r['n']) for r in cur.fetchall()}
        cur.execute('SELECT TABLE_NAME AS n FROM information_schema.VIEWS WHERE TABLE_SCHEMA = DATABASE()')
        views = {r['n'] for r in cur.fetchall()}
        cur.execute('SELECT COUNT(*) AS n FROM information_schema.TRIGGERS WHERE TRIGGER_SCHEMA = DATABASE()')
        triggers = cur.fetchone()['n']
    faltam += [n for n in _OBJETOS_ESPERADOS['VIEW'] if n not in views]
    faltam += [n for n in _OBJETOS_ESPERADOS['PROCEDURE'] if ('PROCEDURE', n) not in existentes]
    faltam += [n for n in _OBJETOS_ESPERADOS['FUNCTION'] if ('FUNCTION', n) not in existentes]
    if triggers < 11:
        faltam.append('triggers (triggers.sql)')
    return faltam


def _conferir_conexao_ao_subir():
    """Testa o MySQL ao subir e avisa em 1 linha. Nunca pergunta nada: o servidor sempre inicia."""
    cfg = config_banco()
    try:
        conectar().close()
        origem = f" — testou {len(_senhas_candidatas())} senha(s) encontrada(s)" if len(_senhas_candidatas()) > 1 else ''
        print(f"✔ MySQL conectado ({cfg['user']}@{cfg['host']}:{cfg['port']}/{cfg['database']}){origem}")
        faltam = _objetos_faltando()
        if faltam:
            print(f"✖ Faltam {len(faltam)} objeto(s) no banco: {', '.join(faltam[:6])}{' ...' if len(faltam) > 6 else ''}. "
                  "Execute no MySQL, nesta ordem: functions.sql, procedures.sql, triggers.sql, views.sql")
        else:
            print('✔ Views, functions, procedures e triggers do banco encontradas')
    except mysql.connector.Error as e:
        if e.errno == 1045:
            achadas = ', '.join(sorted(_LIDO_DOS_ARQUIVOS)) or 'nenhuma'
            print(f"✖ MySQL recusou a senha. Senhas testadas: {len([x for x in _senhas_candidatas() if x])}. "
                  f"Chaves lidas do .env: {achadas}. Use DB_PASSWORD=suasenha no Backend/.env")
        elif e.errno == 1049:
            print(f"✖ O banco '{cfg['database']}' não existe. Rode o script SQL de criação primeiro.")
        elif e.errno in (2003, 2002):
            print('✖ O MySQL não está rodando. Inicie o serviço (ou o XAMPP).')
        else:
            print(f'✖ {e}')


if __name__ == '__main__':
    # com debug ligado o Flask roda o arquivo 2x (reloader); só o processo principal faz o diagnóstico.
    if os.environ.get('WERKZEUG_RUN_MAIN') != 'true':
        _conferir_conexao_ao_subir()
    port = int(os.getenv('PORT', 5000))
    app.run(host='127.0.0.1', port=port, debug=(os.getenv('FLASK_DEBUG', '1') == '1'))
