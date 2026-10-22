// ═══════════════════════════════════════════════════════════
//  modulos.js — CRUD completo + consultas SQL
//  Depende de script.js (api, esc, mostrarToast, formatar*, validar*, máscaras...)
//  Conteúdo:
//    1. Modal e helpers de formulário
//    2. Equipamento (detalhes / editar) e Chamado (editar / histórico)
//    3. Página Manutenções
//    4. Página Usuários
//    5. Página Consultas SQL (resultado, gráfico, CSV, PDF)
// ═══════════════════════════════════════════════════════════

// ── 1. MODAL E FORMULÁRIOS ───────────────────────────────────

let _modalAtual = null;

/**
 * Abre um modal. botoes: [{ rotulo, tipo: 'primario'|'secundario'|'perigo', aoClicar(btn, modal) }]
 * Devolve { fundo, corpo, fechar }.
 */
function abrirModal({ titulo, conteudo, botoes = [], largura = 520 }) {
    fecharModal(true);

    const fundo = document.createElement('div');
    fundo.className = 'modal-fundo';
    fundo.innerHTML = `
        <div class="modal" role="dialog" aria-modal="true" aria-label="${esc(titulo)}" style="max-width:${Number(largura)}px" tabindex="-1">
            <div class="modal-topo">
                <h2>${esc(titulo)}</h2>
                <button type="button" class="modal-fechar" aria-label="Fechar">×</button>
            </div>
            <div class="modal-corpo">${conteudo}</div>
            <div class="modal-rodape"></div>
        </div>`;

    const modal = fundo.querySelector('.modal');
    const rodape = fundo.querySelector('.modal-rodape');
    const api_ = { fundo, corpo: fundo.querySelector('.modal-corpo'), fechar: fecharModal };

    botoes.forEach(b => {
        const el = document.createElement('button');
        el.type = 'button';
        el.className = 'modal-btn modal-btn-' + (b.tipo || 'secundario');
        el.textContent = b.rotulo;
        el.addEventListener('click', () => (b.aoClicar ? b.aoClicar(el, api_) : fecharModal()));
        rodape.appendChild(el);
    });
    if (!botoes.length) rodape.remove();

    fundo.addEventListener('mousedown', ev => { if (ev.target === fundo) fecharModal(); });
    fundo.querySelector('.modal-fechar').addEventListener('click', fecharModal);

    document.body.appendChild(fundo);
    document.body.classList.add('modal-aberto');
    requestAnimationFrame(() => fundo.classList.add('aberto'));

    const primeiro = fundo.querySelector('input:not([readonly]):not([type=hidden]), select, textarea');
    (primeiro || modal).focus();

    _modalAtual = fundo;
    return api_;
}

function fecharModal(imediato = false) {
    if (!_modalAtual) return;
    const fundo = _modalAtual;
    _modalAtual = null;
    document.body.classList.remove('modal-aberto');
    // tira os ids na hora: durante a animação de saída não pode haver ids repetidos com um modal novo
    fundo.querySelectorAll('[id]').forEach(el => el.removeAttribute('id'));
    if (imediato === true) return fundo.remove();
    fundo.classList.remove('aberto');
    setTimeout(() => fundo.remove(), 180);
}

document.addEventListener('keydown', ev => { if (ev.key === 'Escape') fecharModal(); });

/** Gera um .form-group. opcoes = [[valor, rotulo], ...] vira <select>; tipo 'textarea' vira <textarea>. */
function campoForm({ id, rotulo, tipo = 'text', valor = '', opcoes = null, placeholder = '',
                     somenteLeitura = false, maxlength = null, modo = null, dica = '' }) {
    const attrs = [
        `id="${esc(id)}"`,
        somenteLeitura ? 'readonly' : '',
        placeholder ? `placeholder="${esc(placeholder)}"` : '',
        maxlength ? `maxlength="${Number(maxlength)}"` : '',
        modo ? `inputmode="${esc(modo)}"` : '',
    ].filter(Boolean).join(' ');

    let controle;
    if (opcoes) {
        controle = `<select id="${esc(id)}" ${somenteLeitura ? 'disabled' : ''}>${opcoes.map(([v, r]) =>
            `<option value="${esc(v)}" ${String(v) === String(valor ?? '') ? 'selected' : ''}>${esc(r)}</option>`).join('')}</select>`;
    } else if (tipo === 'textarea') {
        controle = `<textarea ${attrs} rows="3">${esc(valor)}</textarea>`;
    } else {
        controle = `<input type="${esc(tipo)}" ${attrs} value="${esc(valor)}" autocomplete="off" />`;
    }
    return `<div class="form-group"><label for="${esc(id)}">${esc(rotulo)}</label>${controle}${dica ? `<small class="dica-campo">${esc(dica)}</small>` : ''}</div>`;
}

const val = id => (document.getElementById(id)?.value ?? '').trim();

function ligarMascara(id, transformar) {
    const el = document.getElementById(id);
    if (el) el.addEventListener('input', () => { el.value = transformar(el.value); });
}

function hoje() {
    const d = new Date();
    return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
}

function formatarMoeda(n) {
    return Number(n || 0).toLocaleString('pt-BR', { style: 'currency', currency: 'BRL' });
}

function formatarDataHora(d) {
    if (!d) return '—';
    const dt = new Date(d);
    if (isNaN(dt)) return '—';
    return dt.toLocaleDateString('pt-BR') + ' ' + dt.toLocaleTimeString('pt-BR', { hour: '2-digit', minute: '2-digit' });
}

// Aceita "1.234,56", "1234.56", "12,5" → número (ou NaN)
function lerDecimal(texto) {
    let t = String(texto).trim().replace(/\s/g, '');
    if (t === '') return 0;
    if (t.includes(',')) t = t.replace(/\./g, '').replace(',', '.');
    return /^\d+(\.\d{1,2})?$/.test(t) ? parseFloat(t) : NaN;
}

const somenteDecimal = v => v.replace(/[^\d.,]/g, '');

const OPCOES_CATEGORIA = [['Informatica', 'Informática'], ['Mobiliario', 'Mobiliário'], ['Climatizacao', 'Climatização'],
                          ['Eletrodomestico', 'Eletrodoméstico'], ['Outro', 'Outro']];
const OPCOES_STATUS_EQUIP = ['disponivel', 'em_uso', 'em_manutencao', 'inativo'].map(v => [v, formatarStatus(v)]);
const OPCOES_CONSERVACAO = ['otimo', 'bom', 'regular', 'ruim', 'inutilizavel'].map(v => [v, formatarStatus(v)]);
const OPCOES_PRIORIDADE = ['baixa', 'media', 'alta', 'critica'].map(v => [v, formatarPrioridade(v)]);

/** Mostra pares rótulo/valor em grade (usado nos modais de detalhes). */
function gradeDetalhes(pares) {
    return `<dl class="detalhes">${pares.map(([r, v]) =>
        `<div><dt>${esc(r)}</dt><dd>${v === '' || v == null ? '—' : v}</dd></div>`).join('')}</dl>`;
}

// ── 2. EQUIPAMENTO E CHAMADO ─────────────────────────────────

async function detalhesEquipamento(id) {
    try {
        const e = await api(`/equipamentos/${id}`);
        abrirModal({
            titulo: e.nome,
            largura: 560,
            conteudo:
                gradeDetalhes([
                    ['Nº do patrimônio', esc(e.numero_patrimonio)],
                    ['Categoria', esc((OPCOES_CATEGORIA.find(([v]) => v === e.categoria) || [, e.categoria])[1])],
                    ['Localização', esc(e.localizacao)],
                    ['Conservação', esc(formatarStatus(e.estado_conservacao))],
                    ['Status', `<span class="badge status-${esc(e.status)}">${esc(formatarStatus(e.status))}</span>`],
                    ['Aquisição', esc(formatarData(e.data_aquisicao))],
                    ['Descrição', esc(e.descricao)],
                ]) +
                `<h3 class="modal-subtitulo">Indicadores calculados no banco <small>(functions)</small></h3>` +
                gradeDetalhes([
                    ['Custo total de manutenção', esc(formatarMoeda(e.custo_total_manutencao))],
                    ['Total de chamados', esc(e.total_chamados)],
                    ['Disponibilidade', esc(e.disponibilidade)],
                ]),
            botoes: [
                { rotulo: 'Editar', tipo: 'primario', aoClicar: () => editarEquipamento(id) },
                { rotulo: 'Fechar', aoClicar: fecharModal },
            ],
        });
    } catch (err) { mostrarToast(err.message, 'erro'); }
}

async function editarEquipamento(id) {
    let e = todosEquipamentos.find(x => x.id_equipamento === id);
    if (!e) {
        try { e = await api(`/equipamentos/${id}`); } catch (err) { return mostrarToast(err.message, 'erro'); }
    }
    abrirModal({
        titulo: 'Editar equipamento',
        conteudo:
            campoForm({ id: 'ed-patrimonio', rotulo: 'Nº do patrimônio (não editável)', valor: e.numero_patrimonio, somenteLeitura: true }) +
            campoForm({ id: 'ed-nome', rotulo: 'Nome *', valor: e.nome, maxlength: 100 }) +
            campoForm({ id: 'ed-descricao', rotulo: 'Descrição', tipo: 'textarea', valor: e.descricao }) +
            campoForm({ id: 'ed-localizacao', rotulo: 'Localização', valor: e.localizacao, maxlength: 100 }) +
            campoForm({ id: 'ed-categoria', rotulo: 'Categoria', opcoes: OPCOES_CATEGORIA, valor: e.categoria }) +
            campoForm({ id: 'ed-conservacao', rotulo: 'Estado de conservação', opcoes: OPCOES_CONSERVACAO, valor: e.estado_conservacao }) +
            campoForm({ id: 'ed-status', rotulo: 'Status', opcoes: OPCOES_STATUS_EQUIP, valor: e.status }),
        botoes: [
            { rotulo: 'Cancelar', aoClicar: fecharModal },
            {
                rotulo: 'Salvar', tipo: 'primario',
                aoClicar: async (btn, modal) => {
                    limparTodosErros();
                    if (!val('ed-nome')) return mostrarErroCampo('ed-nome', 'O nome é obrigatório.');
                    definirCarregando(btn, true, 'Salvando...');
                    try {
                        await api(`/equipamentos/${id}`, {
                            method: 'PUT',
                            corpo: {
                                nome: val('ed-nome'), descricao: val('ed-descricao'), localizacao: val('ed-localizacao'),
                                categoria: val('ed-categoria'), estado_conservacao: val('ed-conservacao'), status: val('ed-status'),
                            },
                        });
                        mostrarToast('Equipamento atualizado.', 'sucesso');
                        modal.fechar();
                        carregarEquipamentos();
                    } catch (err) {
                        mostrarToast(err.message, 'erro');
                        definirCarregando(btn, false);
                    }
                },
            },
        ],
    });
}

async function editarChamado(id) {
    const c = todosChamados.find(x => x.id_chamado === id);
    if (!c) return mostrarToast('Chamado não encontrado na lista. Recarregue a página.', 'erro');

    const opcoesEquip = [['', '— sem equipamento —'],
        ...todosEquipamentos.map(e => [e.id_equipamento, `${e.nome} · Nº ${e.numero_patrimonio}`])];

    abrirModal({
        titulo: `Editar chamado #${id}`,
        conteudo:
            campoForm({ id: 'ch-descricao', rotulo: 'Descrição do problema *', tipo: 'textarea', valor: c.descricao_problema }) +
            campoForm({ id: 'ch-prioridade', rotulo: 'Prioridade', opcoes: OPCOES_PRIORIDADE, valor: c.prioridade }) +
            campoForm({ id: 'ch-equipamento', rotulo: 'Equipamento', opcoes: opcoesEquip, valor: c.id_equipamento ?? '' }) +
            campoForm({ id: 'ch-obs', rotulo: 'Observações', tipo: 'textarea', valor: c.observacoes }) +
            `<p class="dica-campo">Para mudar o status (aberto, em análise, concluído...) use os botões do próprio chamado — assim fica registrado no histórico.</p>`,
        botoes: [
            { rotulo: 'Cancelar', aoClicar: fecharModal },
            {
                rotulo: 'Salvar', tipo: 'primario',
                aoClicar: async (btn, modal) => {
                    limparTodosErros();
                    if (!val('ch-descricao')) return mostrarErroCampo('ch-descricao', 'A descrição é obrigatória.');
                    definirCarregando(btn, true, 'Salvando...');
                    try {
                        await api(`/chamados/${id}`, {
                            method: 'PUT',
                            corpo: {
                                descricao_problema: val('ch-descricao'), prioridade: val('ch-prioridade'),
                                id_equipamento: val('ch-equipamento') ? Number(val('ch-equipamento')) : null,
                                observacoes: val('ch-obs'),
                            },
                        });
                        mostrarToast(`Chamado #${id} atualizado.`, 'sucesso');
                        modal.fechar();
                        carregarChamados();
                    } catch (err) {
                        mostrarToast(err.message, 'erro');
                        definirCarregando(btn, false);
                    }
                },
            },
        ],
    });
}

async function historicoChamado(id) {
    const c = todosChamados.find(x => x.id_chamado === id);
    try {
        const hist = await api(`/chamados/${id}/historico`);
        const eventos = [];
        if (c) eventos.push({ titulo: 'Chamado aberto', detalhe: '', data: c.data_abertura });
        hist.forEach(h => eventos.push({
            titulo: `${formatarStatus(h.status_anterior)} para ${formatarStatus(h.status_novo)}`,
            detalhe: [h.usuario ? `por ${h.usuario}` : '', h.observacao || ''].filter(Boolean).join(' · '),
            data: h.data_alteracao,
        }));
        const linha = ev => `
            <li><span class="linha-ponto"></span>
                <div><strong>${esc(ev.titulo)}</strong>
                ${ev.detalhe ? `<span class="linha-detalhe">${esc(ev.detalhe)}</span>` : ''}
                <span class="linha-data">${esc(formatarDataHora(ev.data))}</span></div></li>`;
        abrirModal({
            titulo: `Histórico do chamado #${id}`,
            conteudo: eventos.length
                ? `<ol class="linha-tempo">${eventos.map(linha).join('')}</ol>`
                : '<p class="recent-empty">Sem registros.</p>',
            botoes: [{ rotulo: 'Fechar', aoClicar: fecharModal }],
        });
    } catch (err) { mostrarToast(err.message, 'erro'); }
}

// ── 3. MANUTENÇÕES ───────────────────────────────────────────

let todasManutencoes = [];
let situacaoManutencao = '';

async function carregarManutencoes() {
    try {
        todasManutencoes = await api('/manutencoes');
        renderizarManutencoes();
    } catch (e) {
        mostrarToast(e.message, 'erro');
        document.getElementById('corpo-manutencoes').innerHTML =
            '<tr class="empty-row"><td colspan="8">Erro ao carregar manutenções.</td></tr>';
    }
}

function renderizarManutencoes() {
    const andamento = todasManutencoes.filter(m => !m.data_fim);
    document.getElementById('man-total').textContent = todasManutencoes.length;
    document.getElementById('man-andamento').textContent = andamento.length;
    document.getElementById('man-custo').textContent = formatarMoeda(todasManutencoes.reduce((s, m) => s + Number(m.custo || 0), 0));

    const lista = todasManutencoes.filter(m =>
        situacaoManutencao === '' || (situacaoManutencao === 'andamento' ? !m.data_fim : !!m.data_fim));
    const corpo = document.getElementById('corpo-manutencoes');
    if (!lista.length) {
        corpo.innerHTML = '<tr class="empty-row"><td colspan="8">Nenhuma manutenção encontrada.</td></tr>';
        return;
    }
    corpo.innerHTML = lista.map(m => `
        <tr>
            <td>${Number(m.id_manutencao)}</td>
            <td>${esc(m.equipamento)}</td>
            <td class="celula-descricao" title="${esc(m.descricao_problema)}">${esc(m.descricao_problema)}</td>
            <td>${esc(m.tecnico_responsavel)}</td>
            <td>${esc(formatarData(m.data_inicio))}</td>
            <td>${m.data_fim ? esc(formatarData(m.data_fim)) : '<span class="badge status-em_execucao">Em andamento</span>'}</td>
            <td>${esc(formatarMoeda(m.custo))}</td>
            <td class="celula-acoes">
                ${m.data_fim ? '' : `<button class="btn-acao btn-acao-ok" data-acao="concluir" data-id="${Number(m.id_manutencao)}">Concluir</button>`}
                <button class="btn-acao" data-acao="editar" data-id="${Number(m.id_manutencao)}">Editar</button>
                <button class="btn-danger" data-acao="remover" data-id="${Number(m.id_manutencao)}">Remover</button>
            </td>
        </tr>`).join('');
}

function setupManutencoes() {
    document.getElementById('btn-nova-manutencao').addEventListener('click', () => formManutencao(null));

    document.getElementById('filtros-manutencao').addEventListener('click', ev => {
        const btn = ev.target.closest('.filtro-btn');
        if (!btn) return;
        document.querySelectorAll('#filtros-manutencao .filtro-btn').forEach(b => b.classList.remove('active'));
        btn.classList.add('active');
        situacaoManutencao = btn.dataset.situacao;
        renderizarManutencoes();
    });

    document.getElementById('corpo-manutencoes').addEventListener('click', ev => {
        const btn = ev.target.closest('[data-acao]');
        if (!btn) return;
        const id = Number(btn.dataset.id);
        const m = todasManutencoes.find(x => x.id_manutencao === id);
        if (btn.dataset.acao === 'editar') formManutencao(m);
        if (btn.dataset.acao === 'concluir') concluirManutencao(m, btn);
        if (btn.dataset.acao === 'remover') removerManutencao(m, btn);
    });

    carregarManutencoes();
}

function corpoManutencao(m, dados = {}) {
    return {
        data_inicio: dados.data_inicio, data_fim: dados.data_fim || null,
        tecnico_responsavel: dados.tecnico_responsavel,
        descricao_servico: dados.descricao_servico ?? m?.descricao_servico ?? '',
        custo: dados.custo,
    };
}

async function concluirManutencao(m, btn) {
    btn.disabled = true;
    try {
        await api(`/manutencoes/${m.id_manutencao}`, {
            method: 'PUT',
            corpo: corpoManutencao(m, {
                data_inicio: String(m.data_inicio).slice(0, 10), data_fim: hoje(),
                tecnico_responsavel: m.tecnico_responsavel, descricao_servico: m.descricao_servico, custo: m.custo,
            }),
        });
        mostrarToast('Manutenção concluída. Se era a última do equipamento, ele voltou para "Disponível".', 'sucesso');
        carregarManutencoes();
    } catch (e) {
        mostrarToast(e.message, 'erro');
        btn.disabled = false;
    }
}

async function removerManutencao(m, btn) {
    if (!confirm(`Remover a manutenção #${m.id_manutencao} (${m.equipamento})?`)) return;
    btn.disabled = true;
    try {
        await api(`/manutencoes/${m.id_manutencao}`, { method: 'DELETE' });
        mostrarToast('Manutenção removida.', 'sucesso');
        carregarManutencoes();
    } catch (e) {
        mostrarToast(e.message, 'erro');
        btn.disabled = false;
    }
}

/** m = null → nova manutenção; m = objeto → edição. */
async function formManutencao(m) {
    const editando = !!m;
    let chamados = [], equipamentos = [];
    try {
        [chamados, equipamentos] = await Promise.all([api('/chamados'), api('/equipamentos')]);
    } catch (e) { return mostrarToast(e.message, 'erro'); }

    const opcoesChamado = chamados.map(c => [c.id_chamado,
        `#${c.id_chamado} — ${String(c.descricao_problema).slice(0, 40)} (${formatarStatus(c.status)})`]);
    const opcoesEquip = equipamentos.map(e => [e.id_equipamento, `${e.nome} · Nº ${e.numero_patrimonio}`]);

    const topo = editando
        ? campoForm({ id: 'mn-chamado-txt', rotulo: 'Chamado', valor: `#${m.id_chamado} — ${m.descricao_problema}`, somenteLeitura: true }) +
          campoForm({ id: 'mn-equip-txt', rotulo: 'Equipamento', valor: `${m.equipamento} · Nº ${m.numero_patrimonio}`, somenteLeitura: true })
        : campoForm({ id: 'mn-chamado', rotulo: 'Chamado *', opcoes: [['', 'Selecione o chamado...'], ...opcoesChamado] }) +
          campoForm({ id: 'mn-equip', rotulo: 'Equipamento *', opcoes: [['', 'Selecione o equipamento...'], ...opcoesEquip] });

    const modal = abrirModal({
        titulo: editando ? `Editar manutenção #${m.id_manutencao}` : 'Nova manutenção',
        conteudo: topo +
            campoForm({ id: 'mn-inicio', rotulo: 'Data de início *', tipo: 'date', valor: editando ? String(m.data_inicio).slice(0, 10) : hoje() }) +
            campoForm({ id: 'mn-tecnico', rotulo: 'Técnico responsável *', valor: m?.tecnico_responsavel, maxlength: 100 }) +
            campoForm({ id: 'mn-servico', rotulo: 'Descrição do serviço', tipo: 'textarea', valor: m?.descricao_servico }) +
            campoForm({ id: 'mn-custo', rotulo: 'Custo (R$)', valor: editando ? String(m.custo ?? 0).replace('.', ',') : '', placeholder: '0,00', modo: 'decimal' }) +
            campoForm({ id: 'mn-fim', rotulo: 'Data de conclusão', tipo: 'date', valor: m?.data_fim ? String(m.data_fim).slice(0, 10) : '',
                       dica: 'Deixe em branco se a manutenção ainda está em andamento.' }),
        botoes: [
            { rotulo: 'Cancelar', aoClicar: fecharModal },
            {
                rotulo: 'Salvar', tipo: 'primario',
                aoClicar: async (btn, mdl) => {
                    limparTodosErros();
                    let ok = true;
                    const erro = (id, msg) => { mostrarErroCampo(id, msg); ok = false; };

                    if (!editando && !val('mn-chamado')) erro('mn-chamado', 'Selecione o chamado.');
                    if (!editando && !val('mn-equip')) erro('mn-equip', 'Selecione o equipamento.');
                    if (!val('mn-inicio')) erro('mn-inicio', 'Informe a data de início.');
                    if (!val('mn-tecnico')) erro('mn-tecnico', 'Informe o técnico responsável.');
                    const custo = lerDecimal(val('mn-custo'));
                    if (Number.isNaN(custo)) erro('mn-custo', 'Custo inválido. Exemplo: 150,00');
                    if (val('mn-fim') && val('mn-inicio') && val('mn-fim') < val('mn-inicio'))
                        erro('mn-fim', 'A conclusão não pode ser antes do início.');
                    if (!ok) return;

                    const dados = {
                        data_inicio: val('mn-inicio'), data_fim: val('mn-fim') || null,
                        tecnico_responsavel: val('mn-tecnico'), descricao_servico: val('mn-servico'), custo,
                    };
                    definirCarregando(btn, true, 'Salvando...');
                    try {
                        if (editando) {
                            await api(`/manutencoes/${m.id_manutencao}`, { method: 'PUT', corpo: dados });
                        } else {
                            await api('/manutencoes', {
                                corpo: { ...dados, id_chamado: Number(val('mn-chamado')), id_equipamento: Number(val('mn-equip')) },
                            });
                        }
                        mostrarToast(editando ? 'Manutenção atualizada.' : 'Manutenção registrada.', 'sucesso');
                        mdl.fechar();
                        carregarManutencoes();
                    } catch (e) {
                        mostrarToast(e.message, 'erro');
                        definirCarregando(btn, false);
                    }
                },
            },
        ],
    });

    ligarMascara('mn-tecnico', somenteLetras);
    ligarMascara('mn-custo', somenteDecimal);

    // Ao escolher o chamado, já seleciona o equipamento dele
    document.getElementById('mn-chamado')?.addEventListener('change', ev => {
        const c = chamados.find(x => String(x.id_chamado) === ev.target.value);
        if (c?.id_equipamento) document.getElementById('mn-equip').value = String(c.id_equipamento);
    });
    return modal;
}

// ── 4. USUÁRIOS ──────────────────────────────────────────────

let todosUsuarios = [];

async function carregarUsuarios() {
    try {
        todosUsuarios = await api('/usuarios');
        renderizarUsuarios();
    } catch (e) {
        mostrarToast(e.message, 'erro');
        document.getElementById('corpo-usuarios').innerHTML =
            '<tr class="empty-row"><td colspan="7">Erro ao carregar usuários.</td></tr>';
    }
}

function renderizarUsuarios() {
    const termo = val('filtro-usuario').toLowerCase();
    const lista = todosUsuarios.filter(u =>
        !termo || (u.nome || '').toLowerCase().includes(termo) || (u.email || '').toLowerCase().includes(termo));
    const corpo = document.getElementById('corpo-usuarios');
    if (!lista.length) {
        corpo.innerHTML = '<tr class="empty-row"><td colspan="7">Nenhum usuário encontrado.</td></tr>';
        return;
    }
    corpo.innerHTML = lista.map(u => `
        <tr>
            <td>${esc(u.nome)}${u.ativo === 0 ? ' <span class="badge status-inativo">Inativo</span>' : ''}</td>
            <td>${esc(u.email)}</td>
            <td>${esc(u.cpf) || '—'}</td>
            <td>${esc(u.telefone) || '—'}</td>
            <td><span class="badge tipo-${esc(u.tipo_usuario)}">${u.tipo_usuario === 'admin' ? 'Administrador' : 'Usuário'}</span></td>
            <td>${Number(u.chamados_abertos || 0)}</td>
            <td class="celula-acoes">
                <button class="btn-acao" data-acao="editar" data-id="${Number(u.id_usuario)}">Editar</button>
                <button class="btn-danger" data-acao="remover" data-id="${Number(u.id_usuario)}">Remover</button>
            </td>
        </tr>`).join('');
}

function setupUsuarios() {
    document.getElementById('btn-novo-usuario').addEventListener('click', formNovoUsuario);
    document.getElementById('filtro-usuario').addEventListener('input', renderizarUsuarios);
    document.getElementById('corpo-usuarios').addEventListener('click', ev => {
        const btn = ev.target.closest('[data-acao]');
        if (!btn) return;
        const u = todosUsuarios.find(x => x.id_usuario === Number(btn.dataset.id));
        if (btn.dataset.acao === 'editar') formEditarUsuario(u);
        if (btn.dataset.acao === 'remover') removerUsuario(u, btn);
    });
    carregarUsuarios();
}

async function removerUsuario(u, btn) {
    if (u.id_usuario === obterUsuario()?.id_usuario) {
        return mostrarToast('Você não pode remover o usuário com o qual está logado.', 'aviso');
    }
    if (!confirm(`Remover o usuário "${u.nome}"? Essa ação não pode ser desfeita.`)) return;
    btn.disabled = true;
    try {
        await api(`/usuarios/${u.id_usuario}`, { method: 'DELETE' });
        mostrarToast('Usuário removido.', 'sucesso');
        carregarUsuarios();
    } catch (e) {
        mostrarToast(e.message, 'erro'); // ex.: usuário com chamados (409)
        btn.disabled = false;
    }
}

function formEditarUsuario(u) {
    const modal = abrirModal({
        titulo: 'Editar usuário',
        conteudo:
            campoForm({ id: 'us-nome', rotulo: 'Nome completo *', valor: u.nome, maxlength: 100 }) +
            campoForm({ id: 'us-email', rotulo: 'E-mail *', tipo: 'email', valor: u.email, maxlength: 100 }) +
            campoForm({ id: 'us-cpf', rotulo: 'CPF (não editável)', valor: u.cpf, somenteLeitura: true }) +
            campoForm({ id: 'us-telefone', rotulo: 'Telefone', valor: u.telefone, placeholder: '(00) 00000-0000', modo: 'numeric', maxlength: 15 }) +
            campoForm({ id: 'us-nasc', rotulo: 'Data de nascimento', tipo: 'date', valor: u.data_nascimento ? String(u.data_nascimento).slice(0, 10) : '' }) +
            campoForm({ id: 'us-tipo', rotulo: 'Perfil', opcoes: [['usuario', 'Usuário'], ['admin', 'Administrador']], valor: u.tipo_usuario }) +
            campoForm({ id: 'us-ativo', rotulo: 'Situação', opcoes: [['1', 'Ativo'], ['0', 'Inativo (não consegue entrar)']], valor: u.ativo === 0 ? '0' : '1' }) +
            campoForm({ id: 'us-senha', rotulo: 'Nova senha', tipo: 'password', placeholder: 'Deixe em branco para manter a atual',
                       dica: 'Mín. 8 caracteres, com maiúscula, minúscula, número e caractere especial.' }) +
            campoForm({ id: 'us-senha2', rotulo: 'Confirmar nova senha', tipo: 'password' }),
        botoes: [
            { rotulo: 'Cancelar', aoClicar: fecharModal },
            {
                rotulo: 'Salvar', tipo: 'primario',
                aoClicar: async (btn, modal) => {
                    limparTodosErros();
                    let ok = true;
                    const erro = (id, msg) => { mostrarErroCampo(id, msg); ok = false; };
                    if (!val('us-nome')) erro('us-nome', 'O nome é obrigatório.');
                    if (!validarEmail(val('us-email'))) erro('us-email', MSG_EMAIL_INVALIDO);
                    const faltas = val('us-senha') ? validarSenha(document.getElementById('us-senha').value) : [];
                    if (faltas.length) erro('us-senha', 'Senha precisa de: ' + faltas.join(', ') + '.');
                    if (document.getElementById('us-senha2').value !== document.getElementById('us-senha').value)
                        erro('us-senha2', 'As senhas não conferem.');
                    if (!ok) return;

                    definirCarregando(btn, true, 'Salvando...');
                    try {
                        await api(`/usuarios/${u.id_usuario}`, {
                            method: 'PUT',
                            corpo: {
                                nome: val('us-nome'), email: val('us-email').toLowerCase(), telefone: val('us-telefone'),
                                data_nascimento: val('us-nasc') || null, tipo_usuario: val('us-tipo'), ativo: val('us-ativo') === '1',
                                senha: document.getElementById('us-senha').value,
                            },
                        });
                        // se editou a si mesmo, atualiza a sessão e o nome no menu
                        const logado = obterUsuario();
                        if (logado && logado.id_usuario === u.id_usuario) {
                            localStorage.setItem('usuario', JSON.stringify({ ...logado, nome: val('us-nome'),
                                email: val('us-email').toLowerCase(), tipo_usuario: val('us-tipo') }));
                            carregarUsuario();
                        }
                        mostrarToast('Usuário atualizado.', 'sucesso');
                        modal.fechar();
                        carregarUsuarios();
                    } catch (e) {
                        mostrarToast(e.message, 'erro');
                        definirCarregando(btn, false);
                    }
                },
            },
        ],
    });
    ligarMascara('us-nome', somenteLetras);
    ligarMascara('us-telefone', mascaraTelefone);
    setupMostrarSenha(modal.corpo);
    ligarConfirmacaoSenha('us-senha', 'us-senha2');
}

function formNovoUsuario() {
    const modal = abrirModal({
        titulo: 'Novo usuário',
        conteudo:
            campoForm({ id: 'nu-nome', rotulo: 'Nome completo *', maxlength: 100 }) +
            campoForm({ id: 'nu-email', rotulo: 'E-mail *', tipo: 'email', maxlength: 100, placeholder: 'nome@dominio.com' }) +
            campoForm({ id: 'nu-cpf', rotulo: 'CPF *', placeholder: '000.000.000-00', modo: 'numeric', maxlength: 14 }) +
            campoForm({ id: 'nu-telefone', rotulo: 'Telefone', placeholder: '(00) 00000-0000', modo: 'numeric', maxlength: 15 }) +
            campoForm({ id: 'nu-nasc', rotulo: 'Data de nascimento *', tipo: 'date' }) +
            campoForm({ id: 'nu-senha', rotulo: 'Senha *', tipo: 'password',
                       dica: 'Mín. 8 caracteres, com maiúscula, minúscula, número e caractere especial.' }) +
            campoForm({ id: 'nu-senha2', rotulo: 'Confirmar senha *', tipo: 'password' }),
        botoes: [
            { rotulo: 'Cancelar', aoClicar: fecharModal },
            {
                rotulo: 'Cadastrar', tipo: 'primario',
                aoClicar: async (btn, modal) => {
                    limparTodosErros();
                    let ok = true;
                    const erro = (id, msg) => { mostrarErroCampo(id, msg); ok = false; };
                    if (!val('nu-nome')) erro('nu-nome', 'O nome é obrigatório.');
                    if (!validarEmail(val('nu-email'))) erro('nu-email', MSG_EMAIL_INVALIDO);
                    if (!validarCPF(val('nu-cpf'))) erro('nu-cpf', 'CPF inválido.');
                    if (!val('nu-nasc')) erro('nu-nasc', 'Informe a data de nascimento.');
                    const faltas = validarSenha(document.getElementById('nu-senha').value);
                    if (faltas.length) erro('nu-senha', 'Senha precisa de: ' + faltas.join(', ') + '.');
                    if (document.getElementById('nu-senha2').value !== document.getElementById('nu-senha').value)
                        erro('nu-senha2', 'As senhas não conferem.');
                    if (!ok) return;

                    definirCarregando(btn, true, 'Cadastrando...');
                    try {
                        await api('/cadastrar', {
                            corpo: {
                                nome: val('nu-nome'), email: val('nu-email').toLowerCase(), senha: document.getElementById('nu-senha').value,
                                cpf: val('nu-cpf'), telefone: val('nu-telefone'), data_nascimento: val('nu-nasc'),
                            },
                        });
                        mostrarToast('Usuário cadastrado.', 'sucesso');
                        modal.fechar();
                        carregarUsuarios();
                    } catch (e) {
                        mostrarToast(e.message, 'erro');
                        definirCarregando(btn, false);
                    }
                },
            },
        ],
    });
    ligarMascara('nu-nome', somenteLetras);
    ligarMascara('nu-cpf', v => mascaraCPF(v.replace(/\D/g, '').slice(0, 11)));
    ligarMascara('nu-telefone', mascaraTelefone);
    setupMostrarSenha(modal.corpo);
    ligarConfirmacaoSenha('nu-senha', 'nu-senha2');
}

// ── 5. CONSULTAS SQL ─────────────────────────────────────────

let catalogoConsultas = null;
let consultaAtual = null;      // objeto do catálogo
let resultadoAtual = null;     // { colunas, linhas }

const PALETA_GRAFICO = ['#3b82f6', '#22c55e', '#f59e0b', '#ef4444', '#8b5cf6', '#14b8a6'];

function rotuloOpcaoParametro(p, v) {
    if (v === '') return p.nome === 'status' ? 'Todos os status' : 'Todas as categorias';
    return p.nome === 'status' ? formatarStatus(v) : v;
}

async function carregarCatalogo() {
    const lista = document.getElementById('consultas-lista');
    try {
        catalogoConsultas = await api('/consultas');
    } catch (e) {
        lista.innerHTML = '<div class="recent-empty">Erro ao carregar as consultas.</div>';
        return mostrarToast(e.message, 'erro');
    }
    const { niveis, consultas } = catalogoConsultas;
    // "Consultas simples" → "Simples" (rótulo curto da aba)
    const rotuloAba = t => { const r = t.replace(/^Consultas\s+/i, ''); return r.charAt(0).toUpperCase() + r.slice(1); };
    lista.innerHTML = `
        <div class="consultas-abas" role="tablist">
            ${niveis.map(({ id: nivel, titulo }) => `
                <button type="button" class="consulta-aba" role="tab" data-nivel="${esc(nivel)}">
                    ${esc(rotuloAba(titulo))}<span class="aba-contagem">${consultas.filter(c => c.nivel === nivel).length}</span>
                </button>`).join('')}
        </div>
        ${niveis.map(({ id: nivel }) => `
            <div class="consultas-grupo" role="tabpanel" data-nivel="${esc(nivel)}" hidden>
                ${consultas.filter(c => c.nivel === nivel).map(c => `
                    <button type="button" class="consulta-item" data-id="${esc(c.id)}">
                        <span class="chip-id chip-${esc(c.nivel)}">${esc(c.id)}</span>
                        <span>${esc(c.titulo)}</span>
                    </button>`).join('')}
            </div>`).join('')}`;

    lista.addEventListener('click', ev => {
        const aba = ev.target.closest('.consulta-aba');
        if (aba) return mostrarGrupoConsultas(aba.dataset.nivel);
        const item = ev.target.closest('.consulta-item');
        if (item) selecionarConsulta(item.dataset.id);
    });

    const inicial = (location.hash || '').replace('#', '').toUpperCase();
    selecionarConsulta(consultas.some(c => c.id === inicial) ? inicial : consultas[0].id);
}

// Mostra só as consultas do nível escolhido (abas), sem lista rolando
function mostrarGrupoConsultas(nivel) {
    document.querySelectorAll('.consulta-aba').forEach(a => a.classList.toggle('ativa', a.dataset.nivel === nivel));
    document.querySelectorAll('.consultas-grupo').forEach(g => { g.hidden = g.dataset.nivel !== nivel; });
}

function campoParametro(p) {
    const id = 'param-' + p.nome;
    let controle;
    if (p.tipo === 'selecao') {
        controle = `<select id="${id}">${p.opcoes.map(o =>
            `<option value="${esc(o)}" ${o === p.padrao ? 'selected' : ''}>${esc(rotuloOpcaoParametro(p, o))}</option>`).join('')}</select>`;
    } else {
        const tipo = p.tipo === 'numero' ? 'number' : p.tipo === 'data' ? 'date' : 'text';
        controle = `<input id="${id}" type="${tipo}" value="${esc(p.padrao)}" ${p.tipo === 'numero' ? 'min="0" max="1000" step="1"' : ''} />`;
    }
    return `<div class="form-group"><label for="${id}">${esc(p.rotulo)}</label>${controle}</div>`;
}

function selecionarConsulta(id) {
    consultaAtual = catalogoConsultas.consultas.find(c => c.id === id);
    if (!consultaAtual) return;
    const c = consultaAtual;
    try { history.replaceState(null, '', '#' + c.id); } catch { /* file:// em alguns navegadores */ }

    mostrarGrupoConsultas(c.nivel);
    document.querySelectorAll('.consulta-item').forEach(b => b.classList.toggle('ativa', b.dataset.id === id));

    document.getElementById('consulta-painel').innerHTML = `
        <div class="impressao-cabecalho">ISEPAM — Sistema de Patrimônio · Consulta ${esc(c.id)} — ${esc(c.titulo)} · <span id="imp-data"></span></div>
        <div class="consulta-cabecalho">
            <span class="chip-id chip-${esc(c.nivel)}">${esc(c.id)}</span>
            <h2>${esc(c.titulo)}</h2>
        </div>
        <p class="consulta-desc">${esc(c.descricao)}</p>
        <form class="consulta-params" id="consulta-form" autocomplete="off">
            ${c.parametros.map(campoParametro).join('')}
            <button type="submit" class="btn-save">${c.parametros.length ? 'Executar' : 'Executar novamente'}</button>
        </form>

        <div class="resultado-topo">
            <h3 id="resultado-titulo">Resultado</h3>
            <div class="resultado-botoes">
                <button type="button" class="btn-acao" id="btn-csv" disabled>Exportar CSV</button>
                <button type="button" class="btn-acao" id="btn-pdf" disabled>Exportar PDF</button>
            </div>
        </div>
        <div class="chart-card-corpo consulta-grafico" id="consulta-grafico" hidden><canvas id="grafico-consulta"></canvas></div>
        <div class="tabela-rolagem tabela-resultado" id="consulta-tabela"></div>`;

    document.getElementById('consulta-form').addEventListener('submit', ev => { ev.preventDefault(); executarConsulta(); });
    document.getElementById('btn-csv').addEventListener('click', exportarCSV);
    document.getElementById('btn-pdf').addEventListener('click', () => {
        document.getElementById('imp-data').textContent = new Date().toLocaleString('pt-BR');
        window.print();
    });
    executarConsulta();
}

let _execucaoConsulta = 0;

async function executarConsulta() {
    const c = consultaAtual;
    const ticket = ++_execucaoConsulta;   // só a execução mais recente pode atualizar a tela
    const alvo = document.getElementById('consulta-tabela');
    const params = new URLSearchParams();
    c.parametros.forEach(p => params.set(p.nome, document.getElementById('param-' + p.nome).value));

    alvo.innerHTML = '<div class="recent-empty">Executando...</div>';
    try {
        const r = await api(`/consultas/${c.id}?${params}`);
        if (ticket !== _execucaoConsulta) return; // chegou uma resposta mais nova
        resultadoAtual = r;
        document.getElementById('resultado-titulo').textContent =
            `Resultado — ${r.total} ${r.total === 1 ? 'linha' : 'linhas'}`;
        alvo.innerHTML = tabelaResultado(r);
        document.getElementById('btn-csv').disabled = r.total === 0;
        document.getElementById('btn-pdf').disabled = false;
        desenharGraficoConsulta(c, r);
    } catch (e) {
        if (ticket !== _execucaoConsulta) return;
        resultadoAtual = null;
        alvo.innerHTML = `<div class="recent-empty consulta-erro">${esc(e.message)}</div>`;
        document.getElementById('consulta-grafico').hidden = true;
        mostrarToast(e.message, 'erro');
    }
}

function formatarCelula(coluna, v) {
    if (v === null || v === undefined || v === '') return '—';
    if (typeof v === 'number') {
        if (/custo|valor|total_gasto/i.test(coluna)) return formatarMoeda(v);
        return Number.isInteger(v) ? String(v) : v.toLocaleString('pt-BR', { maximumFractionDigits: 2 });
    }
    if (/^\d{4}-\d{2}-\d{2}T/.test(v)) return formatarDataHora(v);
    if (/^\d{4}-\d{2}-\d{2}$/.test(v)) return formatarData(v);
    if (coluna === 'prioridade') return formatarPrioridade(v);
    if (coluna === 'status' || /^estado_/.test(coluna)) return formatarStatus(v);
    return String(v);
}

function tabelaResultado(r) {
    if (!r.total) return '<div class="recent-empty">A consulta não retornou nenhuma linha.</div>';
    return `<table>
        <thead><tr>${r.colunas.map(c => `<th>${esc(c.replace(/_/g, ' '))}</th>`).join('')}</tr></thead>
        <tbody>${r.linhas.map(l => `<tr>${r.colunas.map(c => `<td>${esc(formatarCelula(c, l[c]))}</td>`).join('')}</tr>`).join('')}</tbody>
    </table>`;
}

function desenharGraficoConsulta(c, r) {
    const caixa = document.getElementById('consulta-grafico');
    destruirGrafico('grafico-consulta');
    if (!c.grafico || !r.total || typeof Chart === 'undefined') { caixa.hidden = true; return; }
    caixa.hidden = false;

    const g = c.grafico;
    const rotulos = r.linhas.map(l => formatarCelula(g.rotulo, l[g.rotulo]));
    const rotuloLegenda = col => col.replace(/_/g, ' ');
    const rosca = g.tipo === 'doughnut';

    const datasets = g.valores.map((col, i) => ({
        label: rotuloLegenda(col),
        data: r.linhas.map(l => Number(l[col]) || 0),
        backgroundColor: rosca ? rotulos.map((_, k) => PALETA_GRAFICO[k % PALETA_GRAFICO.length]) : PALETA_GRAFICO[i % PALETA_GRAFICO.length],
        borderColor: g.tipo === 'line' ? PALETA_GRAFICO[i % PALETA_GRAFICO.length] : undefined,
        borderWidth: rosca ? 0 : g.tipo === 'line' ? 2 : 0,
        borderRadius: g.tipo === 'bar' ? 4 : 0,
        tension: 0.3,
        fill: false,
    }));

    new Chart(document.getElementById('grafico-consulta'), {
        type: g.tipo,
        data: { labels: rotulos, datasets },
        options: {
            responsive: true, maintainAspectRatio: false,
            plugins: { legend: { display: rosca || datasets.length > 1, labels: { color: COR_EIXO_GRAFICO } } },
            scales: rosca ? {} : {
                x: { ticks: { color: COR_EIXO_GRAFICO }, grid: { display: false } },
                y: { beginAtZero: true, ticks: { color: COR_EIXO_GRAFICO }, grid: { color: COR_GRADE_GRAFICO } },
            },
        },
    });
}

function exportarCSV() {
    if (!resultadoAtual || !resultadoAtual.total) return;
    const celula = v => {
        const t = v === null || v === undefined ? '' : String(v);
        return /[;"\n]/.test(t) ? `"${t.replace(/"/g, '""')}"` : t;
    };
    const linhas = [resultadoAtual.colunas.map(celula).join(';')]
        .concat(resultadoAtual.linhas.map(l => resultadoAtual.colunas.map(c => celula(l[c])).join(';')));
    // BOM + ponto e vírgula: o Excel em português abre com acentos e colunas corretos
    const blob = new Blob(['﻿' + linhas.join('\r\n')], { type: 'text/csv;charset=utf-8' });
    const a = document.createElement('a');
    a.href = URL.createObjectURL(blob);
    a.download = `consulta-${consultaAtual.id}.csv`;
    document.body.appendChild(a);
    a.click();
    a.remove();
    setTimeout(() => URL.revokeObjectURL(a.href), 1000);
}

// ── INICIALIZAÇÃO ────────────────────────────────────────────

document.addEventListener('DOMContentLoaded', () => {
    if (!obterUsuario()) return; // script.js já redireciona para o login
    if (!ehAdmin() && document.getElementById('corpo-usuarios')) return; // script.js manda de volta ao dashboard
    if (document.getElementById('corpo-manutencoes')) setupManutencoes();
    if (document.getElementById('corpo-usuarios'))    setupUsuarios();
    if (document.getElementById('consultas-lista'))   carregarCatalogo();
});
