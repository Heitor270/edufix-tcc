// ── URL DA API ───────────────────────────────
// Descobre sozinho onde está o backend (resultado guardado em cache):
//  - Aberto pelo próprio Flask (mesma origem) → usa caminho relativo
//  - Aberto direto do arquivo (file://) ou por Live Server → Flask local em 127.0.0.1:5000
const API_LOCAL = 'http://127.0.0.1:5000';
let _apiBase = null;

async function resolverApiBase() {
    if (_apiBase !== null) return _apiBase;

    const { protocol, hostname } = window.location;
    if (protocol === 'file:') return (_apiBase = API_LOCAL);

    const local = hostname === 'localhost' || hostname === '127.0.0.1';
    if (!local) return (_apiBase = '');

    // Se esta origem responde /health em JSON, quem serviu a página foi o próprio Flask
    try {
        const r = await fetch('/health', { cache: 'no-store' });
        const j = await r.json();
        if (j && 'ok' in j) return (_apiBase = '');
    } catch (e) { /* Live Server etc. devolve HTML/404 → cai no fallback */ }
    return (_apiBase = API_LOCAL);
}

const TEMPO_LIMITE_MS = 20000; // desiste da requisição depois de 20s

// ── COMUNICAÇÃO COM A API ─────────────────────

class ErroApi extends Error {
    constructor(mensagem, status = 0, dados = null) {
        super(mensagem);
        this.status = status;
        this.dados = dados;
    }
}

// Faz a requisição e devolve o JSON. Em qualquer falha lança ErroApi com uma mensagem clara:
//   - servidor inacessível / timeout
//   - resposta que não é JSON (ex.: página de erro do navegador)
//   - status HTTP de erro (usa a "mensagem" que o Flask enviou)
async function api(caminho, opcoes = {}) {
    const { corpo, ...resto } = opcoes;
    const init = { ...resto };
    init.headers = { ...(init.headers || {}) };
    const logado = obterUsuario();
    if (logado && logado.id_usuario) init.headers['X-Usuario-Id'] = String(logado.id_usuario);  // backend confere o perfil
    if (corpo !== undefined) {
        init.method = init.method || 'POST';
        init.headers['Content-Type'] = 'application/json';
        init.body = JSON.stringify(corpo);
    }

    const base = await resolverApiBase();
    const controle = new AbortController();
    const timer = setTimeout(() => controle.abort(), TEMPO_LIMITE_MS);
    let res;
    try {
        res = await fetch(base + caminho, { ...init, signal: controle.signal });
    } catch (e) {
        const msg = e.name === 'AbortError'
            ? 'O servidor demorou demais para responder. Tente novamente.'
            : `Não foi possível conectar ao servidor (${base || window.location.origin}). Verifique se o backend (app.py) está rodando.`;
        throw new ErroApi(msg, 0);
    } finally {
        clearTimeout(timer);
    }

    let dados = null;
    try { dados = await res.json(); } catch (e) { /* corpo não é JSON */ }

    if (!res.ok) {
        const msg = (dados && dados.mensagem) || `O servidor respondeu com erro (HTTP ${res.status}).`;
        throw new ErroApi(msg, res.status, dados);
    }
    if (dados === null) throw new ErroApi(`Resposta inválida do servidor (HTTP ${res.status}).`, res.status);
    return dados;
}

// Escapa texto vindo do banco antes de colocar em innerHTML (evita injeção de HTML/JS)
function esc(valor) {
    return String(valor ?? '').replace(/[&<>"']/g, c => (
        { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]
    ));
}

// Lê o usuário salvo no login (sem quebrar se o localStorage estiver corrompido)
function obterUsuario() {
    try { return JSON.parse(localStorage.getItem('usuario')); } catch { return null; }
}

// Desabilita o botão enquanto a requisição roda (evita cliques duplos)
function definirCarregando(btn, carregando, textoCarregando) {
    if (!btn) return;
    if (carregando) {
        btn.dataset.textoOriginal = btn.textContent;
        btn.textContent = textoCarregando;
        btn.disabled = true;
    } else {
        btn.textContent = btn.dataset.textoOriginal || btn.textContent;
        btn.disabled = false;
    }
}

// ── PERFIL: administrador x usuário comum ───
// Só o administrador vê (e acessa) a tela de Usuários. O backend também confere (rotas /usuarios e /admin).
const PAGINAS_SO_ADMIN = ['usuarios.html'];

function ehAdmin() {
    const u = obterUsuario();
    return !!u && u.tipo_usuario === 'admin';
}

// Esconde o que o perfil não pode usar e tira o usuário comum de páginas restritas. Devolve false se redirecionou.
function aplicarPerfil() {
    if (ehAdmin()) return true;
    document.querySelectorAll('a[href="usuarios.html"], [data-so-admin]').forEach(el => el.remove());
    const pagina = (location.pathname.split('/').pop() || '').toLowerCase();
    if (PAGINAS_SO_ADMIN.includes(pagina)) {
        try { sessionStorage.setItem('aviso_acesso', 'Acesso restrito a administradores.'); } catch { /* sem sessionStorage */ }
        window.location.replace('dashboard.html');
        return false;
    }
    return true;
}

// Páginas internas exigem login; login e cadastro (.auth-body) não
function exigirLogin() {
    if (document.body.classList.contains('auth-body')) return true;
    if (!obterUsuario()) {
        window.location.replace('index.html');
        return false;
    }
    return true;
}

// ── SPLASH SCREEN ────────────────────────────

function iniciarSplash() {
    const splash = document.createElement('div');
    splash.id = 'splash';
    splash.innerHTML = `
        <div class="splash-conteudo">
            <div class="splash-logo">ISEPAM</div>
            <p class="splash-sub">Sistema de Gestão Patrimonial</p>
            <div class="splash-barra"><div class="splash-progresso"></div></div>
        </div>
    `;
    document.body.prepend(splash);

    // Fecha após a barra completar
    setTimeout(() => {
        splash.classList.add('splash-saindo');
        setTimeout(() => splash.remove(), 500);
    }, 1400);
}

// ── TRANSIÇÕES DE PÁGINA ──────────────────────

function setupTransicoes() {
    // A animação de entrada (paginaEntrar) já roda via CSS em cada carregamento.
    // Aqui só garantimos que links inativos redirecionam direto, sem delay.
    document.querySelectorAll('.nav-item[href]').forEach(link => {
        link.addEventListener('click', e => {
            const destino = link.getAttribute('href');
            if (!destino || link.classList.contains('active')) return;
            // Redireciona imediatamente — a entrada da nova página cuida da animação
            window.location.href = destino;
        });
    });
}

// ── MODO ESCURO ───────────────────────────────

function aplicarTema() {
    const tema = localStorage.getItem('tema') || 'light';
    document.documentElement.setAttribute('data-theme', tema);
    document.querySelectorAll('.theme-toggle, .theme-toggle-auth').forEach(btn => {
        btn.textContent = tema === 'dark' ? 'Modo Claro' : 'Modo Escuro';
    });
}

function alternarTema() {
    const novo = (localStorage.getItem('tema') || 'light') === 'dark' ? 'light' : 'dark';
    localStorage.setItem('tema', novo);
    aplicarTema();
}

// ── TOAST NOTIFICATIONS ───────────────────────

function mostrarToast(mensagem, tipo = 'sucesso') {
    document.querySelectorAll('.toast').forEach(t => t.remove());

    const toast = document.createElement('div');
    toast.className = `toast toast-${tipo}`;
    toast.innerHTML = `
        <span class="toast-msg"></span>
        <button class="toast-close" onclick="this.parentElement.remove()">×</button>
    `;
    toast.querySelector('.toast-msg').textContent = mensagem;
    document.body.appendChild(toast);

    requestAnimationFrame(() => toast.classList.add('show'));

    setTimeout(() => {
        toast.classList.remove('show');
        setTimeout(() => toast.remove(), 400);
    }, tipo === 'erro' ? 5500 : 4000);
}

// ── VALIDAÇÕES ────────────────────────────────

// Regra geral de e-mail (aceita pessoal, institucional e de prefeitura):
//   algo escrito antes do @  +  @  +  domínio com ponto  +  terminação de 2+ letras
//   ok:  ana@gmail.com · joao@ifrj.edu.br · maria@campos.rj.gov.br · setor-ti@escola.org
//   não: ana@  ·  @gmail.com  ·  ana@gmail  ·  ana@@gmail.com  ·  ana..x@gmail.com  ·  ana @gmail.com
const REGEX_EMAIL = /^[A-Za-z0-9](?:[A-Za-z0-9._%+\-]*[A-Za-z0-9])?@(?:[A-Za-z0-9](?:[A-Za-z0-9\-]*[A-Za-z0-9])?\.)+[A-Za-z]{2,}$/;
const MSG_EMAIL_INVALIDO = 'Informe um e-mail válido, como nome@dominio.com ou nome@orgao.gov.br.';

function validarEmail(email) {
    email = String(email).trim();
    return email.length <= 100 && !email.includes('..') && REGEX_EMAIL.test(email);
}

function validarSenha(senha) {
    const erros = [];
    if (senha.length < 8)               erros.push('mínimo de 8 caracteres');
    if (!/[A-Z]/.test(senha))           erros.push('uma letra maiúscula');
    if (!/[a-z]/.test(senha))           erros.push('uma letra minúscula');
    if (!/[0-9]/.test(senha))           erros.push('um número');
    if (!/[!@#$%^&*()\-_,.?":{}|<>]/.test(senha)) erros.push('um caractere especial (!@#$...)');
    return erros; // Array vazio = senha válida
}

// ── MÁSCARA E VALIDAÇÃO DE CPF ───────────────

function mascaraCPF(valor) {
    valor = valor.replace(/\D/g, '');             // Remove tudo que não é dígito
    valor = valor.replace(/(\d{3})(\d)/, '$1.$2');
    valor = valor.replace(/(\d{3})\.(\d{3})(\d)/, '$1.$2.$3');
    valor = valor.replace(/(\d{3})\.(\d{3})\.(\d{3})(\d{1,2})/, '$1.$2.$3-$4');
    return valor.substring(0, 14);                // Limita ao tamanho do CPF formatado
}

function validarCPF(cpf) {
    cpf = cpf.replace(/\D/g, '');
    if (cpf.length !== 11) return false;
    if (/^(\d)\1+$/.test(cpf)) return false; // Rejeita CPFs com todos os dígitos iguais (ex: 111.111.111-11)

    // Validação do 1º dígito verificador
    let soma = 0;
    for (let i = 0; i < 9; i++) soma += parseInt(cpf[i]) * (10 - i);
    let resto = (soma * 10) % 11;
    if (resto === 10 || resto === 11) resto = 0;
    if (resto !== parseInt(cpf[9])) return false;

    // Validação do 2º dígito verificador
    soma = 0;
    for (let i = 0; i < 10; i++) soma += parseInt(cpf[i]) * (11 - i);
    resto = (soma * 10) % 11;
    if (resto === 10 || resto === 11) resto = 0;
    return resto === parseInt(cpf[10]);
}

// ── MÁSCARA DE TELEFONE ───────────────────────

function mascaraTelefone(valor) {
    const digitos = valor.replace(/\D/g, '').substring(0, 11); // até DDD + 9 dígitos
    const t = digitos.length;

    if (t === 0) return '';
    if (t <= 2)  return `(${digitos}`;
    if (t <= 6)  return `(${digitos.slice(0, 2)}) ${digitos.slice(2)}`;
    if (t <= 10) return `(${digitos.slice(0, 2)}) ${digitos.slice(2, 6)}-${digitos.slice(6)}`;
    return `(${digitos.slice(0, 2)}) ${digitos.slice(2, 7)}-${digitos.slice(7)}`;
}

function setupMascaras() {
    const campoCPF = document.getElementById('cpf');
    if (campoCPF) {
        campoCPF.placeholder = '000.000.000-00';
        campoCPF.maxLength = 14;
        campoCPF.addEventListener('input', function () {
            // Extrai só os dígitos e reformata — cursor vai pro fim naturalmente
            const soDigitos = this.value.replace(/\D/g, '').substring(0, 11);
            this.value = mascaraCPF(soDigitos);
        });
    }

    const campoTelefone = document.getElementById('telefone');
    if (campoTelefone) {
        campoTelefone.placeholder = '(00) 00000-0000';
        campoTelefone.maxLength = 15;
        campoTelefone.setAttribute('inputmode', 'numeric');
        campoTelefone.addEventListener('input', function () {
            this.value = mascaraTelefone(this.value);
        });
    }

    // Campos que são um número de identificação: só dígitos, nada de letra ou símbolo
    ['numero_patrimonio', 'patrimonio-chamado'].forEach(id => {
        const campo = document.getElementById(id);
        if (!campo) return;
        campo.setAttribute('inputmode', 'numeric');
        campo.maxLength = 12;
        campo.addEventListener('input', function () {
            this.value = somenteDigitos(this.value);
        });
    });

    // Nome completo: só letras e espaço, sem número nem símbolo
    const campoNomeUsuario = document.querySelector('.auth-card #nome');
    if (campoNomeUsuario) {
        campoNomeUsuario.addEventListener('input', function () {
            this.value = somenteLetras(this.value);
        });
    }
}

// Mantém só dígitos (0-9)
function somenteDigitos(valor) {
    return valor.replace(/\D/g, '');
}

// Mantém só letras (com acento) e espaço — remove número e símbolo
function somenteLetras(valor) {
    return valor.replace(/[^\p{L}\s]/gu, '');
}

// ── PLACEHOLDER DE FUNDO PARA CAMPOS DE DATA ──
// input[type=date] não aceita o atributo placeholder nativamente, então
// simulamos: escondemos o texto do campo enquanto ele estiver vazio e
// mostramos um rótulo por cima, igual aos outros campos (telefone, email).
function setupPlaceholderData() {
    document.querySelectorAll('.campo-data input[type="date"]').forEach(input => {
        const atualizar = () => input.classList.toggle('tem-valor', !!input.value);
        input.addEventListener('input', atualizar);
        input.addEventListener('change', atualizar);
        atualizar();
    });
}

// Campo de senha fica dentro de .campo-senha (por causa do olhinho); a mensagem entra logo depois dele
function _ancoraErro(campo) { return campo.closest('.campo-senha') || campo; }

function _removerErroDe(campo) {
    const ancora = _ancoraErro(campo);
    const prox = ancora.nextElementSibling;
    if (prox && prox.classList.contains('campo-erro-inline')) prox.remove();
    // campo de data: o erro mora dentro do próprio wrapper .campo-data
    const caixaData = campo.closest('.campo-data');
    if (caixaData) caixaData.querySelectorAll('.campo-erro-inline').forEach(e => e.remove());
}

function mostrarErroCampo(id, mensagem) {
    const campo = document.getElementById(id);
    if (!campo) return;

    campo.classList.add('campo-invalido');

    // Remove só o erro anterior DESTE campo (os dos outros campos continuam visíveis)
    _removerErroDe(campo);

    if (mensagem) {
        const span = document.createElement('span');
        span.className = 'campo-erro-inline';
        span.textContent = mensagem;
        const ancora = _ancoraErro(campo);
        if (ancora !== campo || !campo.parentElement.classList.contains('campo-data')) {
            ancora.insertAdjacentElement('afterend', span);
        } else {
            campo.parentElement.appendChild(span);   // campo de data: erro dentro do wrapper, como antes
        }
    }

    // Limpa o erro quando o usuário começa a digitar
    campo.addEventListener('input', () => limparErroCampo(id), { once: true });
    campo.addEventListener('change', () => limparErroCampo(id), { once: true });
}

function limparErroCampo(id) {
    const campo = document.getElementById(id);
    if (!campo) return;
    campo.classList.remove('campo-invalido');
    _removerErroDe(campo);
}

function limparTodosErros() {
    document.querySelectorAll('.campo-invalido').forEach(c => c.classList.remove('campo-invalido'));
    document.querySelectorAll('.campo-erro-inline').forEach(e => e.remove());
}

// ── NAVEGAÇÃO COM ENTER ───────────────────────

function setupEnterNavigation() {
    const seletor = 'input:not([type="file"]), select, textarea';
    const campos = Array.from(document.querySelectorAll(seletor));

    campos.forEach((campo, i) => {
        campo.addEventListener('keydown', (e) => {
            if (e.key !== 'Enter') return;
            e.preventDefault();

            const proximo = campos[i + 1];
            if (proximo) {
                proximo.focus();
            } else {
                // Último campo: dispara o botão principal
                const btn = document.querySelector('.btn-primary, .btn-save');
                if (btn) btn.click();
            }
        });
    });
}

// ── FORÇA DA SENHA (indicador visual) ─────────

function setupIndicadorSenha() {
    const campo = document.getElementById('senha');
    if (!campo) return;

    // Só roda na página de cadastro (tem campo CPF)
    if (!document.getElementById('cpf')) return;

    const indicador = document.createElement('div');
    indicador.id = 'indicador-senha';
    indicador.className = 'indicador-senha';
    indicador.style.display = 'none'; // Esconde até o usuário começar a digitar
    indicador.innerHTML = `
        <div class="forca-wrap">
            <div class="barra-forca">
                <div class="barra-segmento" id="seg1"></div>
                <div class="barra-segmento" id="seg2"></div>
                <div class="barra-segmento" id="seg3"></div>
                <div class="barra-segmento" id="seg4"></div>
            </div>
            <span class="forca-texto" id="forca-texto"></span>
        </div>
        <ul class="requisitos-senha" id="requisitos-lista"></ul>
    `;

    // Insere logo depois do input de senha (dentro do card)
    (campo.closest('.campo-senha') || campo).insertAdjacentElement('afterend', indicador);

    campo.addEventListener('input', () => {
        const val = campo.value;

        if (!val) {
            indicador.style.display = 'none';
            return;
        }

        indicador.style.display = 'block';

        const erros = validarSenha(val);
        const forca = 5 - erros.length; // 0 a 5

        const cores  = ['#ef4444', '#f97316', '#eab308', '#22c55e'];
        const labels = ['Muito fraca', 'Fraca', 'Razoável', 'Boa', 'Forte'];
        const cor    = cores[Math.min(forca - 1, 3)] || '#ef4444';

        ['seg1','seg2','seg3','seg4'].forEach((id, i) => {
            document.getElementById(id).style.background =
                i < Math.ceil(forca * 4 / 5) ? cor : 'var(--border)';
        });

        document.getElementById('forca-texto').textContent  = labels[Math.min(forca, 4)] || '';
        document.getElementById('forca-texto').style.color  = forca >= 4 ? '#22c55e' : forca >= 3 ? '#eab308' : '#ef4444';

        const requisitos = [
            { ok: val.length >= 8,                                      texto: 'Mínimo 8 caracteres' },
            { ok: /[A-Z]/.test(val),                                    texto: 'Letra maiúscula' },
            { ok: /[a-z]/.test(val),                                    texto: 'Letra minúscula' },
            { ok: /[0-9]/.test(val),                                    texto: 'Número' },
            { ok: /[!@#$%^&*()\-_,.?":{}|<>]/.test(val),              texto: 'Caractere especial' },
        ];

        document.getElementById('requisitos-lista').innerHTML =
            requisitos.map(r => `<li class="${r.ok ? 'req-ok' : 'req-falta'}">${r.texto}</li>`).join('');
    });
}

// ── VER / ESCONDER SENHA + CONFIRMAÇÃO ───────

const ICONE_OLHO = '<svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M1 12s4-7 11-7 11 7 11 7-4 7-11 7S1 12 1 12z"/><circle cx="12" cy="12" r="3"/></svg>';
const ICONE_OLHO_RISCADO = '<svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M17.94 17.94A10.9 10.9 0 0 1 12 19c-7 0-11-7-11-7a19.8 19.8 0 0 1 5.06-5.94M9.9 4.24A10.9 10.9 0 0 1 12 4c7 0 11 7 11 7a19.8 19.8 0 0 1-3.17 4.19M14.12 14.12a3 3 0 1 1-4.24-4.24"/><line x1="1" y1="1" x2="23" y2="23"/></svg>';

// Coloca um botão "olhinho" em cada campo de senha (clicar alterna entre ••••• e texto)
function envolverCampoSenha(input) {
    if (input.closest('.campo-senha')) return;
    const caixa = document.createElement('div');
    caixa.className = 'campo-senha';
    input.parentNode.insertBefore(caixa, input);
    caixa.appendChild(input);

    const btn = document.createElement('button');
    btn.type = 'button';
    btn.className = 'btn-olho';
    btn.title = 'Mostrar senha';
    btn.setAttribute('aria-label', 'Mostrar senha');
    btn.innerHTML = ICONE_OLHO;
    btn.addEventListener('click', () => {
        const mostrar = input.type === 'password';
        input.type = mostrar ? 'text' : 'password';
        btn.title = mostrar ? 'Ocultar senha' : 'Mostrar senha';
        btn.setAttribute('aria-label', btn.title);
        btn.innerHTML = mostrar ? ICONE_OLHO_RISCADO : ICONE_OLHO;
        input.focus();
    });
    caixa.appendChild(btn);
}

function setupMostrarSenha(raiz = document) {
    raiz.querySelectorAll('input[type="password"]').forEach(envolverCampoSenha);
}

// Aviso ao vivo "as senhas conferem / não são iguais" (senhaId + confirmaId são ids de inputs)
function ligarConfirmacaoSenha(senhaId, confirmaId) {
    const senha = document.getElementById(senhaId);
    const confirma = document.getElementById(confirmaId);
    if (!senha || !confirma) return;

    const aviso = document.createElement('div');
    aviso.className = 'senha-confere';
    aviso.hidden = true;
    (confirma.closest('.campo-senha') || confirma).insertAdjacentElement('afterend', aviso);

    const atualizar = () => {
        if (!confirma.value) { aviso.hidden = true; return; }
        const igual = senha.value === confirma.value;
        aviso.hidden = false;
        aviso.className = 'senha-confere ' + (igual ? 'senha-confere-ok' : 'senha-confere-erro');
        aviso.textContent = igual ? 'As senhas conferem' : 'As senhas não são iguais';
    };
    senha.addEventListener('input', atualizar);
    confirma.addEventListener('input', atualizar);
}

// ── AUTENTICAÇÃO ─────────────────────────────

async function login() {
    limparTodosErros();
    const erro = document.getElementById('erro');
    erro.textContent = '';
    const email = document.getElementById('email').value.trim();
    const senha = document.getElementById('senha').value;
    let valido = true;

    if (!email) {
        mostrarErroCampo('email', 'O e-mail é obrigatório.');
        valido = false;
    } else if (!validarEmail(email)) {
        mostrarErroCampo('email', MSG_EMAIL_INVALIDO);
        valido = false;
    }

    if (!senha) {
        mostrarErroCampo('senha', 'A senha é obrigatória.');
        valido = false;
    }

    if (!valido) return;

    const btn = document.querySelector('.btn-primary');
    definirCarregando(btn, true, 'Entrando...');
    try {
        const data = await api('/login', { corpo: { email, senha } });
        if (data.sucesso) {
            localStorage.setItem('usuario', JSON.stringify(data.usuario));
            iniciarSplash();
            setTimeout(() => window.location.href = 'dashboard.html', 1400);
            return;
        }
        erro.textContent = data.mensagem || 'Não foi possível entrar.';
    } catch (e) {
        erro.textContent = e.message;
    }
    definirCarregando(btn, false);
}

async function cadastrar() {
    limparTodosErros();
    const erro = document.getElementById('erro');
    erro.textContent = '';
    const campos = {
        nome:            document.getElementById('nome').value.trim(),
        email:           document.getElementById('email').value.trim(),
        senha:           document.getElementById('senha').value,
        cpf:             document.getElementById('cpf').value.replace(/\D/g, ''),
        telefone:        document.getElementById('telefone').value.trim(),
        data_nascimento: document.getElementById('data_nascimento').value || null
    };

    let valido = true;

    if (!campos.nome) {
        mostrarErroCampo('nome', 'O nome é obrigatório.');
        valido = false;
    }

    if (!campos.email) {
        mostrarErroCampo('email', 'O e-mail é obrigatório.');
        valido = false;
    } else if (!validarEmail(campos.email)) {
        mostrarErroCampo('email', MSG_EMAIL_INVALIDO);
        valido = false;
    }

    if (!campos.senha) {
        mostrarErroCampo('senha', 'A senha é obrigatória.');
        valido = false;
    } else {
        const errosSenha = validarSenha(campos.senha);
        if (errosSenha.length > 0) {
            mostrarErroCampo('senha', `A senha precisa ter: ${errosSenha.join(', ')}.`);
            valido = false;
        }
    }

    const confirmacao = document.getElementById('confirmar_senha').value;
    if (!confirmacao) {
        mostrarErroCampo('confirmar_senha', 'Confirme a senha digitando-a novamente.');
        valido = false;
    } else if (confirmacao !== campos.senha) {
        mostrarErroCampo('confirmar_senha', 'As senhas não conferem.');
        valido = false;
    }

    if (!campos.cpf) {
        mostrarErroCampo('cpf', 'O CPF é obrigatório.');
        valido = false;
    } else if (!validarCPF(campos.cpf)) {
        mostrarErroCampo('cpf', 'CPF inválido. Verifique os dígitos informados.');
        valido = false;
    }

    const digitosTelefone = campos.telefone.replace(/\D/g, '');
    if (digitosTelefone && digitosTelefone.length < 10) {
        mostrarErroCampo('telefone', 'Telefone incompleto. Informe o DDD + número.');
        valido = false;
    }

    if (!campos.data_nascimento) {
        mostrarErroCampo('data_nascimento', 'A data de nascimento é obrigatória.');
        valido = false;
    }

    if (!valido) return;

    const btn = document.querySelector('.btn-primary');
    definirCarregando(btn, true, 'Cadastrando...');
    try {
        const data = await api('/cadastrar', { corpo: campos });
        if (data.sucesso) {
            mostrarToast('Cadastro realizado com sucesso!', 'sucesso');
            setTimeout(() => window.location.href = 'index.html', 1200);
            return;
        }
        erro.textContent = data.mensagem || 'Não foi possível cadastrar.';
    } catch (e) {
        erro.textContent = e.message;
    }
    definirCarregando(btn, false);
}

function sair() {
    iniciarSplash();
    setTimeout(() => {
        localStorage.removeItem('usuario');
        window.location.href = 'index.html';
    }, 1400);
}

// ── USUÁRIO LOGADO ────────────────────────────

function carregarUsuario() {
    const el = document.getElementById('usuario-nome');
    if (!el) return;
    const usuario = obterUsuario();
    if (usuario) el.textContent = 'Olá, ' + usuario.nome;
}

// ── HELPERS ──────────────────────────────────

function formatarStatus(status) {
    const mapa = {
        aberto: 'Aberto', em_analise: 'Em Análise', em_execucao: 'Em Execução',
        concluido: 'Concluído', cancelado: 'Cancelado',
        disponivel: 'Disponível', em_uso: 'Em Uso',
        em_manutencao: 'Em Manutenção', inativo: 'Inativo',
        otimo: 'Ótimo', bom: 'Bom', regular: 'Regular',
        ruim: 'Ruim', inutilizavel: 'Inutilizável'
    };
    return mapa[status] || status;
}

function formatarPrioridade(p) {
    return { baixa:'Baixa', media:'Média', alta:'Alta', critica:'Crítica' }[p] || p;
}

function formatarData(d) {
    if (!d) return '—';
    const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(d);
    const dt = m ? new Date(+m[1], +m[2] - 1, +m[3]) : new Date(d);
    return isNaN(dt) ? '—' : dt.toLocaleDateString('pt-BR');
}

// ── DASHBOARD ─────────────────────────────────

async function carregarDashboard() {
    try {
        const equipamentos = await api('/equipamentos');
        const total      = document.getElementById('total-itens');
        const manutencao = document.getElementById('em-manutencao');
        if (total)      total.textContent = equipamentos.length;
        if (manutencao) manutencao.textContent = equipamentos.filter(e => e.status === 'em_manutencao').length;
        renderGraficoDoughnut(
            contarPorCampo(equipamentos, 'status'), 'grafico-equipamentos', CORES_STATUS_EQUIPAMENTO
        );
    } catch (e) {
        mostrarToast(e.message, 'erro');
    }

    try {
        const chamados = await api('/chamados');
        const totalChamados = document.getElementById('total-chamados');
        if (totalChamados) totalChamados.textContent = chamados.length;
        renderGraficoBarrasStatus(
            contarPorCampo(chamados, 'status'), 'grafico-chamados-status', CORES_STATUS_CHAMADO
        );

        const recenteContainer = document.querySelector('.recent-empty');
        if (recenteContainer && chamados.length > 0) {
            const ultimos = chamados.slice(0, 5); // a API já devolve do mais novo para o mais antigo
            recenteContainer.outerHTML = ultimos.map(c => `
                <div class="recent-item">
                    <span class="badge status-${esc(c.status)}">${esc(formatarStatus(c.status))}</span>
                    <span class="recent-descricao">${esc(c.descricao_problema)}</span>
                    <span class="recent-data">${formatarData(c.data_abertura)}</span>
                </div>
            `).join('');
        }
    } catch (e) { /* o aviso de erro já foi exibido acima */ }
}

// ── GRÁFICOS (Chart.js) ───────────────────────
// Mesma paleta usada nos badges de status, pra não ter cor nova sem motivo.
const CORES_STATUS_CHAMADO = {
    aberto: '#3b82f6', em_analise: '#eab308', em_execucao: '#f97316',
    concluido: '#22c55e', cancelado: '#94a3b8'
};
const CORES_STATUS_EQUIPAMENTO = {
    disponivel: '#22c55e', em_uso: '#3b82f6', em_manutencao: '#f97316', inativo: '#94a3b8'
};
const CORES_CATEGORIA = {
    Informatica: '#3b82f6', Mobiliario: '#8b5cf6', Climatizacao: '#14b8a6',
    Eletrodomestico: '#f97316', Outro: '#94a3b8'
};
const COR_EIXO_GRAFICO = '#94a3b8';
const COR_GRADE_GRAFICO = 'rgba(148, 163, 184, 0.15)';

const _graficosAtivos = {};

function destruirGrafico(canvasId) {
    if (_graficosAtivos[canvasId]) {
        _graficosAtivos[canvasId].destroy();
        delete _graficosAtivos[canvasId];
    }
}

// Conta quantos itens de `lista` têm cada valor do campo `campo`. Ex.: contarPorCampo(chamados, 'status')
function contarPorCampo(lista, campo) {
    const contagem = {};
    lista.forEach(item => {
        const v = item[campo];
        contagem[v] = (contagem[v] || 0) + 1;
    });
    return contagem;
}

// ── CARDS CLICÁVEIS DO DASHBOARD ──────────────
// Cada card (Itens Totais, Chamados Totais, Em Manutenção) aponta pro gráfico
// que ele resume. Clicar rola até o gráfico e destaca ele; "Em Manutenção"
// também realça a fatia específica dentro do gráfico de equipamentos.
function setupCardsClicaveis() {
    document.querySelectorAll('.card-clicavel').forEach(card => {
        const ativar = () => {
            const chartCard = document.getElementById(card.dataset.graficoAlvo);
            if (!chartCard) return;

            document.querySelectorAll('.chart-card').forEach(c => c.classList.remove('chart-card-destacado'));
            document.querySelectorAll('.card-clicavel').forEach(c => c.classList.remove('card-selecionado'));
            chartCard.classList.add('chart-card-destacado');
            card.classList.add('card-selecionado');
            chartCard.scrollIntoView({ behavior: 'smooth', block: 'center' });

            if (card.dataset.destacarFatia) {
                const canvas = chartCard.querySelector('canvas');
                if (canvas) destacarFatiaGrafico(canvas.id, card.dataset.destacarFatia);
            }
        };
        card.addEventListener('click', ativar);
        card.addEventListener('keydown', e => {
            if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); ativar(); }
        });
    });
}

// Simula um "hover" temporário numa fatia específica do gráfico (pelo texto do label),
// pra mostrar visualmente qual pedaço corresponde ao card clicado.
function destacarFatiaGrafico(canvasId, label) {
    const chart = _graficosAtivos[canvasId];
    if (!chart) return;
    const indice = chart.data.labels.indexOf(label);
    if (indice === -1) return;

    const ponto = chart.getDatasetMeta(0).data[indice];
    chart.setActiveElements([{ datasetIndex: 0, index: indice }]);
    chart.tooltip.setActiveElements([{ datasetIndex: 0, index: indice }], { x: ponto.x, y: ponto.y });
    chart.update();

    setTimeout(() => {
        chart.setActiveElements([]);
        chart.tooltip.setActiveElements([], { x: 0, y: 0 });
        chart.update();
    }, 1800);
}

function mostrarVazioGrafico(canvasId, vazio) {
    const canvas = document.getElementById(canvasId);
    const msgVazia = document.getElementById(canvasId + '-vazio');
    if (canvas) canvas.hidden = vazio;
    if (msgVazia) msgVazia.hidden = !vazio;
}

// Gráfico de rosca (ex.: equipamentos por status, ou por categoria)
function renderGraficoDoughnut(contagem, canvasId, mapaCores) {
    const canvas = document.getElementById(canvasId);
    if (!canvas || typeof Chart === 'undefined') return;

    const chaves = Object.keys(contagem).filter(k => contagem[k] > 0);
    if (chaves.length === 0) { mostrarVazioGrafico(canvasId, true); return; }
    mostrarVazioGrafico(canvasId, false);

    destruirGrafico(canvasId);
    _graficosAtivos[canvasId] = new Chart(canvas, {
        type: 'doughnut',
        data: {
            labels: chaves.map(k => formatarStatus(k)),
            datasets: [{
                data: chaves.map(k => contagem[k]),
                backgroundColor: chaves.map(k => mapaCores[k] || '#94a3b8'),
                borderWidth: 0
            }]
        },
        options: {
            responsive: true,
            maintainAspectRatio: false,
            cutout: '64%',
            plugins: {
                legend: {
                    position: 'bottom',
                    labels: { color: COR_EIXO_GRAFICO, font: { family: 'Sora', size: 12 }, padding: 14, boxWidth: 12 }
                }
            }
        }
    });
}

// Gráfico de barras verticais por status (chamados por status)
function renderGraficoBarrasStatus(contagem, canvasId, mapaCores) {
    const canvas = document.getElementById(canvasId);
    if (!canvas || typeof Chart === 'undefined') return;

    const ordem = Object.keys(mapaCores).filter(k => contagem[k] > 0);
    if (ordem.length === 0) { mostrarVazioGrafico(canvasId, true); return; }
    mostrarVazioGrafico(canvasId, false);

    destruirGrafico(canvasId);
    _graficosAtivos[canvasId] = new Chart(canvas, {
        type: 'bar',
        data: {
            labels: ordem.map(k => formatarStatus(k)),
            datasets: [{
                data: ordem.map(k => contagem[k]),
                backgroundColor: ordem.map(k => mapaCores[k]),
                borderRadius: 6,
                maxBarThickness: 46
            }]
        },
        options: {
            responsive: true,
            maintainAspectRatio: false,
            plugins: { legend: { display: false } },
            scales: {
                x: { grid: { display: false }, ticks: { color: COR_EIXO_GRAFICO, font: { family: 'Sora', size: 12 } } },
                y: {
                    beginAtZero: true,
                    ticks: { precision: 0, color: COR_EIXO_GRAFICO, font: { family: 'Sora', size: 11 } },
                    grid: { color: COR_GRADE_GRAFICO }
                }
            }
        }
    });
}

// Gráfico de barras: chamados criados por usuário (top 10, mais ativos primeiro)
function renderGraficoAtividadeUsuarios(usuarios, canvasId) {
    const canvas = document.getElementById(canvasId);
    if (!canvas || typeof Chart === 'undefined') return;

    const top = [...usuarios]
        .filter(u => Number(u.total_chamados_criados ?? 0) > 0)
        .sort((a, b) => Number(b.total_chamados_criados ?? 0) - Number(a.total_chamados_criados ?? 0))
        .slice(0, 10);
    if (top.length === 0) { mostrarVazioGrafico(canvasId, true); return; }
    mostrarVazioGrafico(canvasId, false);

    destruirGrafico(canvasId);
    _graficosAtivos[canvasId] = new Chart(canvas, {
        type: 'bar',
        data: {
            labels: top.map(u => u.nome_usuario),
            datasets: [
                { label: 'Chamados criados', data: top.map(u => Number(u.total_chamados_criados ?? 0)),
                  backgroundColor: '#3b82f6', borderRadius: 6, maxBarThickness: 36 },
                { label: 'Ainda em aberto', data: top.map(u => Number(u.chamados_ainda_abertos ?? 0)),
                  backgroundColor: '#f59e0b', borderRadius: 6, maxBarThickness: 36 }
            ]
        },
        options: {
            responsive: true,
            maintainAspectRatio: false,
            plugins: { legend: { display: true, position: 'bottom',
                                 labels: { color: COR_EIXO_GRAFICO, boxWidth: 12, font: { family: 'Sora', size: 12 } } } },
            scales: {
                x: { grid: { display: false }, ticks: { color: COR_EIXO_GRAFICO, font: { family: 'Sora', size: 12 } } },
                y: {
                    beginAtZero: true,
                    ticks: { precision: 0, color: COR_EIXO_GRAFICO, font: { family: 'Sora', size: 11 } },
                    grid: { color: COR_GRADE_GRAFICO }
                }
            }
        }
    });
}


function renderGraficoCustoEquipamentos(equipamentosResumo, canvasId) {
    const canvas = document.getElementById(canvasId);
    if (!canvas || typeof Chart === 'undefined') return;

    const top = equipamentosResumo
        .filter(e => Number(e.custo_manutencao ?? e.custo_total_manutencao ?? 0) > 0)
        .slice(0, 5);
    if (top.length === 0) { mostrarVazioGrafico(canvasId, true); return; }
    mostrarVazioGrafico(canvasId, false);

    destruirGrafico(canvasId);
    _graficosAtivos[canvasId] = new Chart(canvas, {
        type: 'bar',
        data: {
            labels: top.map(e => e.nome),
            datasets: [{
                data: top.map(e => Number(e.custo_manutencao ?? e.custo_total_manutencao ?? 0)),
                backgroundColor: '#8b5cf6',
                borderRadius: 6,
                maxBarThickness: 28
            }]
        },
        options: {
            indexAxis: 'y',
            responsive: true,
            maintainAspectRatio: false,
            plugins: {
                legend: { display: false },
                tooltip: { callbacks: { label: (ctx) => 'R$ ' + ctx.parsed.x.toFixed(2).replace('.', ',') } }
            },
            scales: {
                x: { beginAtZero: true, ticks: { color: COR_EIXO_GRAFICO, font: { family: 'Sora', size: 11 } }, grid: { color: COR_GRADE_GRAFICO } },
                y: { ticks: { color: COR_EIXO_GRAFICO, font: { family: 'Sora', size: 12 } }, grid: { display: false } }
            }
        }
    });
}

// ── EQUIPAMENTOS ──────────────────────────────

let todosEquipamentos = [];

async function carregarEquipamentos() {
    try {
        todosEquipamentos = await api('/equipamentos');
        filtrarTabela(); // mantém os filtros que já estavam aplicados
    } catch (e) {
        mostrarToast(e.message, 'erro');
        const corpo = document.getElementById('corpo-tabela');
        if (corpo) corpo.innerHTML = '<tr class="empty-row"><td colspan="7">Erro ao carregar o inventário.</td></tr>';
    }
}

function renderizarTabela(lista) {
    const corpo = document.getElementById('corpo-tabela');
    if (!corpo) return;
    if (lista.length === 0) {
        corpo.innerHTML = '<tr class="empty-row"><td colspan="7">Nenhum bem encontrado.</td></tr>';
        return;
    }
    corpo.innerHTML = lista.map(eq => `
        <tr>
            <td>${esc(eq.numero_patrimonio) || '—'}</td>
            <td>${esc(eq.nome)}</td>
            <td>${esc(eq.categoria) || '—'}</td>
            <td>${esc(eq.localizacao) || '—'}</td>
            <td>${esc(formatarStatus(eq.estado_conservacao))}</td>
            <td><span class="badge status-${esc(eq.status)}">${esc(formatarStatus(eq.status))}</span></td>
            <td class="celula-acoes">
                <button class="btn-acao" onclick="detalhesEquipamento(${Number(eq.id_equipamento)})">Detalhes</button>
                <button class="btn-acao" onclick="editarEquipamento(${Number(eq.id_equipamento)})">Editar</button>
                <button class="btn-danger" onclick="deletarEquipamento(${Number(eq.id_equipamento)})">Remover</button>
            </td>
        </tr>
    `).join('');
}

function filtrarTabela() {
    const pat  = document.getElementById('filtro-patrimonio')?.value.toLowerCase() || '';
    const nome = document.getElementById('filtro-nome')?.value.toLowerCase() || '';
    const cat  = document.getElementById('filtro-categoria')?.value || '';
    const st   = document.getElementById('filtro-status')?.value || '';
    renderizarTabela(todosEquipamentos.filter(eq =>
        (eq.numero_patrimonio || '').toLowerCase().includes(pat) &&
        (eq.nome || '').toLowerCase().includes(nome) &&
        (!cat || eq.categoria === cat) &&
        (!st || eq.status === st)
    ));
}

async function deletarEquipamento(id) {
    if (!confirm('Tem certeza que deseja remover este equipamento?')) return;
    try {
        await api(`/equipamentos/${id}`, { method: 'DELETE' });
        mostrarToast('Equipamento removido com sucesso.', 'sucesso');
        carregarEquipamentos();
    } catch (e) {
        mostrarToast(e.message, 'erro');
    }
}

// ── CHAMADOS ──────────────────────────────────

let todosChamados = [];
let filtroChamadoAtual = 'todos';

function aplicarFiltroChamados() {
    renderizarChamados(filtroChamadoAtual === 'todos'
        ? todosChamados
        : todosChamados.filter(c => c.status === filtroChamadoAtual));
}

async function carregarChamados() {
    try {
        const [chamados, equipamentos] = await Promise.all([api('/chamados'), api('/equipamentos')]);
        todosChamados = chamados;
        todosEquipamentos = equipamentos; // usado para mostrar o nome do equipamento em cada chamado
        aplicarFiltroChamados();
    } catch (e) {
        mostrarToast(e.message, 'erro');
        const el = document.getElementById('lista-chamados');
        if (el) {
            el.className = 'recent-empty';
            el.textContent = 'Erro ao carregar chamados.';
        }
    }
}

function renderizarChamados(lista) {
    const el = document.getElementById('lista-chamados');
    if (!el) return;
    if (lista.length === 0) {
        el.className = 'recent-empty';
        el.textContent = 'Nenhum chamado encontrado.';
        return;
    }
    el.className = '';
    el.innerHTML = lista.map(c => `
        <div class="chamado-item">
            <div class="chamado-header">
                <span class="chamado-id">#${Number(c.id_chamado)}</span>
                <span class="badge status-${esc(c.status)}">${esc(formatarStatus(c.status))}</span>
                <span class="badge prioridade-${esc(c.prioridade)}">${esc(formatarPrioridade(c.prioridade))}</span>
                <span class="recent-data">${formatarData(c.data_abertura)}</span>
            </div>
            <div class="chamado-descricao">${esc(c.descricao_problema)}</div>
            <div class="chamado-meta">
                ${nomeEquipamentoChamado(c)}
            </div>
            ${acoesChamado(c)}
        </div>
    `).join('');
}

function nomeEquipamentoChamado(c) {
    if (!c.id_equipamento) return '<span>Sem equipamento vinculado</span>';
    const eq = todosEquipamentos.find(e => e.id_equipamento === c.id_equipamento);
    return eq
        ? `<span>Equipamento: ${esc(eq.nome)}</span>`
        : `<span>Equipamento #${Number(c.id_equipamento)}</span>`;
}

// Estados de fluxo normal (aparecem no seletor). Concluído/Cancelado viram
// ações próprias (Finalizar / Cancelar / Reabrir), não itens do dropdown.
const STATUS_CHAMADO_FLUXO = ['aberto', 'em_analise', 'em_execucao'];
const CHAMADO_FINALIZADO = ['concluido', 'cancelado'];

function acoesChamado(c) {
    const id = Number(c.id_chamado);

    if (CHAMADO_FINALIZADO.includes(c.status)) {
        // Já fechado: só resta reabrir ou remover de vez
        return `
            <div class="chamado-acoes">
                <div class="chamado-acoes-secundarias">
                    <button type="button" class="chamado-link" data-id="${id}" data-acao="historico">Histórico</button>
                    <button type="button" class="chamado-link" data-id="${id}" data-acao="editar">Editar</button>
                    <button type="button" class="chamado-link" data-id="${id}" data-acao="reabrir">Reabrir</button>
                    <button type="button" class="chamado-link chamado-link-perigo" data-id="${id}" data-acao="remover">Remover</button>
                </div>
            </div>`;
    }

    // Em andamento: seletor pro fluxo + finalizar em destaque, cancelar/remover discretos
    return `
        <div class="chamado-acoes">
            <div class="chamado-acoes-principais">
                <select class="chamado-status-select" data-id="${id}" data-atual="${esc(c.status)}">
                    ${STATUS_CHAMADO_FLUXO.map(op =>
                        `<option value="${op}" ${op === c.status ? 'selected' : ''}>${esc(formatarStatus(op))}</option>`
                    ).join('')}
                </select>
                <button type="button" class="chamado-btn-finalizar" data-id="${id}" data-acao="finalizar">Finalizar</button>
            </div>
            <div class="chamado-acoes-secundarias">
                <button type="button" class="chamado-link" data-id="${id}" data-acao="historico">Histórico</button>
                <button type="button" class="chamado-link" data-id="${id}" data-acao="editar">Editar</button>
                <button type="button" class="chamado-link" data-id="${id}" data-acao="cancelar">Cancelar</button>
                <button type="button" class="chamado-link chamado-link-perigo" data-id="${id}" data-acao="remover">Remover</button>
            </div>
        </div>`;
}

// Delegação de evento: funciona mesmo depois que a lista é re-renderizada,
// porque o listener fica no container (#lista-chamados), não em cada elemento.
function setupAcoesChamados() {
    const lista = document.getElementById('lista-chamados');
    if (!lista) return;

    lista.addEventListener('change', (ev) => {
        const select = ev.target.closest('.chamado-status-select');
        if (select) aplicarStatusChamado(select.dataset.id, select.value, select);
    });

    lista.addEventListener('click', (ev) => {
        const btn = ev.target.closest('[data-acao]');
        if (!btn) return;
        const id = btn.dataset.id;

        switch (btn.dataset.acao) {
            case 'finalizar':
                aplicarStatusChamado(id, 'concluido', btn);
                break;
            case 'reabrir':
                aplicarStatusChamado(id, 'aberto', btn);
                break;
            case 'cancelar':
                if (confirm(`Cancelar o chamado #${id}?`)) aplicarStatusChamado(id, 'cancelado', btn);
                break;
            case 'remover':
                removerChamado(id, btn);
                break;
            case 'editar':
                editarChamado(Number(id));      // modulos.js
                break;
            case 'historico':
                historicoChamado(Number(id));   // modulos.js
                break;
        }
    });
}

async function aplicarStatusChamado(id, novoStatus, origem) {
    const usuario = obterUsuario();
    if (!usuario) {
        mostrarToast('Sua sessão expirou. Faça login novamente.', 'erro');
        if (origem.tagName === 'SELECT') origem.value = origem.dataset.atual;
        return;
    }

    origem.disabled = true;
    try {
        await api(`/chamados/${id}/status`, {
            method: 'PUT',
            corpo: { status: novoStatus, id_usuario: usuario.id_usuario }
        });
        mostrarToast(`Chamado #${id} atualizado para "${formatarStatus(novoStatus)}".`, 'sucesso');
        carregarChamados(); // recarrega pra refletir o badge, as ações e o filtro ativo
    } catch (e) {
        mostrarToast(e.message, 'erro');
        if (origem.tagName === 'SELECT') origem.value = origem.dataset.atual;
        origem.disabled = false;
    }
}

async function removerChamado(id, botao) {
    if (!confirm(`Remover o chamado #${id} definitivamente? Essa ação não pode ser desfeita.`)) return;
    botao.disabled = true;
    try {
        await api(`/chamados/${id}`, { method: 'DELETE' });
        mostrarToast(`Chamado #${id} removido.`, 'sucesso');
        carregarChamados();
    } catch (e) {
        mostrarToast(e.message, 'erro'); // ex.: chamado com manutenções vinculadas (409)
        botao.disabled = false;
    }
}


async function abrirChamado() {
    const usuario = obterUsuario();
    if (!usuario) { mostrarToast('Você precisa estar logado.', 'erro'); return; }

    limparTodosErros();
    const patrimonio = document.getElementById('patrimonio-chamado').value.trim();
    const descricao  = document.getElementById('descricao-chamado').value.trim();
    const prioridade = document.getElementById('prioridade-chamado').value;

    let valido = true;

    if (!patrimonio) {
        mostrarErroCampo('patrimonio-chamado', 'O número do patrimônio é obrigatório.');
        valido = false;
    }

    if (!descricao) {
        mostrarErroCampo('descricao-chamado', 'A descrição do problema é obrigatória.');
        valido = false;
    }

    if (!valido) return;

    const btn = document.querySelector('.btn-save');
    definirCarregando(btn, true, 'Abrindo...');
    try {
        const equipamentos = await api('/equipamentos');
        const eq = equipamentos.find(e => (e.numero_patrimonio || '') === patrimonio);
        if (!eq) {
            mostrarErroCampo('patrimonio-chamado', 'Patrimônio não encontrado no inventário.');
            return;
        }

        await api('/chamados', {
            corpo: { id_usuario: usuario.id_usuario, id_equipamento: eq.id_equipamento, prioridade, descricao_problema: descricao }
        });
        mostrarToast('Chamado aberto com sucesso!', 'sucesso');
        document.getElementById('patrimonio-chamado').value = '';
        document.getElementById('descricao-chamado').value  = '';
        carregarChamados();
    } catch (e) {
        mostrarToast(e.message, 'erro');
    } finally {
        definirCarregando(btn, false);
    }
}

function filtrarChamados(status, btn) {
    document.querySelectorAll('.filtro-btn').forEach(b => b.classList.remove('active'));
    btn.classList.add('active');
    filtroChamadoAtual = status;
    aplicarFiltroChamados();
}

// ── RELATÓRIOS ────────────────────────────────

window._abaAtiva = 'patrimonio';

function trocarAba(nome, btn) {
    document.querySelectorAll('.aba').forEach(b => b.classList.remove('active'));
    btn.classList.add('active');
    window._abaAtiva = nome;

    const filtroCategoria = document.getElementById('categoria-relatorio')?.closest('.form-group');
    if (filtroCategoria) filtroCategoria.style.display = nome === 'patrimonio' ? 'block' : 'none';
    const filtroStatus = document.getElementById('filtro-status-chamados');
    if (filtroStatus) filtroStatus.style.display = nome === 'chamados' ? 'block' : 'none';

    // "Visualizar" só faz sentido onde tem filtro pra aplicar (Patrimônio/Chamados).
    // Atividades e Estatísticas carregam sozinhas, então o botão fica escondido nelas.
    const btnVisualizar = document.getElementById('btn-visualizar-relatorio');
    if (btnVisualizar) btnVisualizar.style.display = (nome === 'patrimonio' || nome === 'chamados') ? '' : 'none';

    visualizarRelatorio(); // carrega na hora — não precisa clicar em "Visualizar" pra ver a aba
}

// Retoca a animação de entrada (a mesma usada ao trocar de página) toda vez
// que o conteúdo do relatório muda, já que só editar o innerHTML não reinicia
// uma animação CSS sozinho.
function reanimarResultado() {
    const el = document.getElementById('resultado-relatorio');
    if (!el) return;
    el.classList.remove('resultado-entrando');
    void el.offsetWidth; // força o navegador a "esquecer" o estado anterior antes de reaplicar
    el.classList.add('resultado-entrando');
}

async function visualizarRelatorio() {
    const aba       = window._abaAtiva || 'patrimonio';
    const resultado = document.getElementById('resultado-relatorio');
    if (!resultado) return;
    resultado.innerHTML = '<p style="color:var(--text-mid);padding:16px 0;">Carregando...</p>';

    let url = '';
    if (aba === 'patrimonio') {
        const cat = document.getElementById('categoria-relatorio').value;
        url = '/relatorio/equipamentos';
        if (cat && cat !== 'todas') url += '?categoria=' + encodeURIComponent(cat);
    } else if (aba === 'chamados') {
        const status = document.getElementById('status-relatorio')?.value;
        url = '/relatorio/chamados';
        if (status && status !== 'todos') url += '?status=' + encodeURIComponent(status);
    } else if (aba === 'atividades') {
        url = '/relatorio/usuarios';
    } else {
        url = '/relatorio';
    }

    let data;
    try {
        data = await api(url);
    } catch (e) {
        resultado.innerHTML = `<p style="color:var(--danger);padding:16px 0;">${esc(e.message)}</p>`;
        reanimarResultado();
        return;
    }

    if (!data || (Array.isArray(data) && data.length === 0)) {
        resultado.innerHTML = '<p class="recent-empty">Nenhum dado encontrado.</p>';
        reanimarResultado();
        return;
    }

    const dinheiro = v => 'R$ ' + Number(v || 0).toFixed(2).replace('.', ',');

    if (aba === 'patrimonio') {
        const porCategoria = {};
        data.forEach(e => { const c = e.categoria || 'Outro'; porCategoria[c] = (porCategoria[c] || 0) + 1; });

        resultado.innerHTML = `
            <div class="chart-card chart-card-compacta">
                <h3>Equipamentos por categoria</h3>
                <div class="chart-card-corpo">
                    <canvas id="grafico-relatorio-categoria" height="150"></canvas>
                    <p class="chart-vazio" id="grafico-relatorio-categoria-vazio" hidden>Sem equipamentos pra mostrar.</p>
                </div>
            </div>
            <table>
            <thead><tr><th>Equipamento</th><th>Categoria</th><th>Localização</th><th>Conservação</th><th>Disponibilidade</th><th>Chamados</th><th>Custo Total</th></tr></thead>
            <tbody>${data.map(e => `<tr>
                <td>${esc(e.nome_equipamento ?? e.nome)}</td><td>${esc(e.categoria) || '—'}</td><td>${esc(e.localizacao) || '—'}</td>
                <td>${esc(formatarStatus(e.conservacao ?? e.estado_conservacao))}</td><td>${esc(e.disponibilidade) || '—'}</td>
                <td>${esc(e.total_chamados ?? 0)}</td><td>${dinheiro(e.custo_total_manutencao ?? e.custo_manutencao)}</td>
            </tr>`).join('')}</tbody></table>`;

        renderGraficoDoughnut(porCategoria, 'grafico-relatorio-categoria', CORES_CATEGORIA);
    } else if (aba === 'chamados') {
        resultado.innerHTML = `<table>
            <thead><tr><th>ID</th><th>Status</th><th>Prioridade</th><th>Usuário</th><th>Equipamento</th><th>Dias</th><th>Manutenções</th></tr></thead>
            <tbody>${data.map(c => `<tr>
                <td>#${esc(c.id_chamado)}</td>
                <td><span class="badge status-${esc(c.status)}">${esc(formatarStatus(c.status))}</span></td>
                <td>${esc(formatarPrioridade(c.prioridade))}</td><td>${esc(c.nome_usuario)}</td>
                <td>${esc(c.nome_equipamento) || '—'}</td><td>${esc(c.dias_resolucao ?? '—')}</td><td>${esc(c.total_manutencoes ?? 0)}</td>
            </tr>`).join('')}</tbody></table>`;
    } else if (aba === 'atividades') {
        resultado.innerHTML = `
            <div class="chart-card chart-card-compacta">
                <h3>Chamados criados por usuário</h3>
                <div class="chart-card-corpo">
                    <canvas id="grafico-relatorio-atividade" height="150"></canvas>
                    <p class="chart-vazio" id="grafico-relatorio-atividade-vazio" hidden>Nenhum chamado registrado ainda.</p>
                </div>
            </div>
            <table>
            <thead><tr><th>Usuário</th><th>E-mail</th><th>Perfil</th><th class="col-num">Chamados criados</th><th class="col-num">Em aberto</th><th class="col-num">Interações</th><th>Último chamado</th></tr></thead>
            <tbody>${data.map(u => `<tr>
                <td><strong>${esc(u.nome_usuario)}</strong></td>
                <td>${esc(u.email) || '—'}</td>
                <td><span class="badge ${u.tipo === 'admin' ? 'tipo-admin' : 'tipo-usuario'}">${u.tipo === 'admin' ? 'Administrador' : 'Usuário'}</span></td>
                <td class="col-num">${Number(u.total_chamados_criados ?? 0)}</td>
                <td class="col-num">${Number(u.chamados_ainda_abertos ?? 0) > 0 ? `<span class="badge pendente">${Number(u.chamados_ainda_abertos)}</span>` : '0'}</td>
                <td class="col-num">${Number(u.total_interacoes_status ?? 0)}</td>
                <td>${u.ultimo_chamado_criado ? formatarData(u.ultimo_chamado_criado) : '—'}</td>
            </tr>`).join('')}</tbody></table>`;

        renderGraficoAtividadeUsuarios(data, 'grafico-relatorio-atividade');
    } else {
        resultado.innerHTML = `
            <div class="cards-grid" style="margin:0 0 24px">
                <div class="card"><div class="card-number">${esc(data.total_equipamentos ?? 0)}</div><div class="card-label">Equipamentos</div></div>
                <div class="card"><div class="card-number">${dinheiro(data.custo_total_manutencoes)}</div><div class="card-label">Custo Total Manutenções</div></div>
            </div>
            <div class="charts-grid">
                <div class="chart-card">
                    <h3>Chamados por status</h3>
                    <div class="chart-card-corpo">
                        <canvas id="grafico-relatorio-status" height="220"></canvas>
                        <p class="chart-vazio" id="grafico-relatorio-status-vazio" hidden>Nenhum chamado registrado ainda.</p>
                    </div>
                </div>
                <div class="chart-card">
                    <h3>Top equipamentos por custo de manutenção</h3>
                    <div class="chart-card-corpo">
                        <canvas id="grafico-relatorio-custo" height="220"></canvas>
                        <p class="chart-vazio" id="grafico-relatorio-custo-vazio" hidden>Nenhuma manutenção registrada ainda.</p>
                    </div>
                </div>
            </div>`;

        const contagemStatus = {};
        (data.chamados_por_status || []).forEach(s => { contagemStatus[s.status] = s.total; });
        renderGraficoBarrasStatus(contagemStatus, 'grafico-relatorio-status', CORES_STATUS_CHAMADO);
        renderGraficoCustoEquipamentos(data.equipamentos_resumo || [], 'grafico-relatorio-custo');
    }

    reanimarResultado();
}

// Abre a impressão do navegador; lá basta escolher "Salvar como PDF".
// O CSS @media print esconde menu e botões e deixa só o relatório.
function baixarPDF() {
    window.print();
}

// ── SALVAMENTO DE BEM (com validação) ─────────

async function salvarBem() {
    limparTodosErros();
    const dados = {
        numero_patrimonio:  document.getElementById('numero_patrimonio').value.trim(),
        nome:               document.getElementById('nome').value.trim(),
        descricao:          document.getElementById('descricao').value.trim(),
        localizacao:        document.getElementById('localizacao').value.trim(),
        estado_conservacao: document.getElementById('estado_conservacao').value,
        categoria:          document.getElementById('categoria').value,
        status:             document.getElementById('status').value,
        data_aquisicao:     document.getElementById('data_aquisicao').value || null
    };

    let valido = true;

    if (!dados.numero_patrimonio) {
        mostrarErroCampo('numero_patrimonio', 'O número do patrimônio é obrigatório.');
        valido = false;
    }
    if (!dados.nome) {
        mostrarErroCampo('nome', 'O nome do item é obrigatório.');
        valido = false;
    }
    if (!dados.data_aquisicao) {
        mostrarErroCampo('data_aquisicao', 'A data de aquisição é obrigatória.');
        valido = false;
    }

    if (!valido) return;

    const btn = document.querySelector('.btn-save');
    definirCarregando(btn, true, 'Salvando...');
    try {
        await api('/equipamentos', { corpo: dados });
        mostrarToast('Bem cadastrado com sucesso!', 'sucesso');
        setTimeout(() => window.location.href = 'inventario.html', 1200);
        return;
    } catch (e) {
        mostrarToast(e.message, 'erro');
    }
    definirCarregando(btn, false);
}

// ── INICIALIZAÇÃO ─────────────────────────────

document.addEventListener('DOMContentLoaded', () => {
    if (!exigirLogin()) return; // páginas internas sem login voltam para o index.html
    if (!aplicarPerfil()) return; // usuário comum em página de admin volta para o dashboard

    aplicarTema();
    try {   // aviso deixado por uma página restrita
        const aviso = sessionStorage.getItem('aviso_acesso');
        if (aviso) { sessionStorage.removeItem('aviso_acesso'); mostrarToast(aviso, 'aviso'); }
    } catch { /* sem sessionStorage */ }
    carregarUsuario();
    setupMostrarSenha();
    ligarConfirmacaoSenha('senha', 'confirmar_senha');
    setupEnterNavigation();
    setupIndicadorSenha();
    setupMascaras();
    setupPlaceholderData();
    setupTransicoes();

    if (document.getElementById('corpo-tabela'))   carregarEquipamentos();
    if (document.getElementById('total-itens'))    { setupCardsClicaveis(); carregarDashboard(); }
    if (document.getElementById('lista-chamados')) { setupAcoesChamados(); carregarChamados(); }
    if (document.getElementById('resultado-relatorio')) visualizarRelatorio();
});
