"""
Catálogo das consultas do sistema (somente metadados).

O SQL de cada consulta NÃO fica aqui nem aparece no site: ele vive no banco de dados
(views.sql e procedures.sql). Aqui só dizemos, para cada consulta, qual objeto do banco
chamar e como mostrar o resultado na tela:

  objeto  -> {'tipo': 'view' | 'procedure', 'nome': ...}
  ordem   -> ORDER BY aplicado ao ler uma view (garante a ordem em qualquer versão do MySQL)
"""

CATEGORIAS = ['Informatica', 'Mobiliario', 'Climatizacao', 'Eletrodomestico', 'Outro']
STATUS_CHAMADO = ['aberto', 'em_analise', 'em_execucao', 'concluido', 'cancelado']

P_CATEGORIA = {'nome': 'categoria', 'rotulo': 'Categoria', 'tipo': 'selecao', 'padrao': '',
               'opcoes': [''] + CATEGORIAS}
P_STATUS = {'nome': 'status', 'rotulo': 'Status do chamado', 'tipo': 'selecao', 'padrao': '',
            'opcoes': [''] + STATUS_CHAMADO}

NIVEIS = {
    'simples': 'Consultas simples',
    'intermediaria': 'Consultas intermediárias',
    'avancada': 'Consultas complexas',
    'procedure': 'Resumos',
}

CONSULTAS = [
    # ───────── SIMPLES ─────────
    {
        'id': 'S1', 'nivel': 'simples',
        'titulo': 'Equipamentos disponíveis',
        'descricao': 'Lista tudo o que está livre para uso, em ordem alfabética.',
        'parametros': [],
        'objeto': {'tipo': 'view', 'nome': 'vw_equipamentos_disponiveis'},
        'ordem': 'nome',
    },
    {
        'id': 'S2', 'nivel': 'simples',
        'titulo': 'Equipamentos por categoria',
        'descricao': 'Filtra o inventário por categoria (deixe em branco para ver todas).',
        'parametros': [P_CATEGORIA],
        'objeto': {'tipo': 'procedure', 'nome': 'sp_equipamentos_por_categoria'},
    },
    {
        'id': 'S3', 'nivel': 'simples',
        'titulo': 'Chamados urgentes em andamento',
        'descricao': 'Chamados de prioridade alta ou crítica que ainda não foram encerrados.',
        'parametros': [],
        'objeto': {'tipo': 'view', 'nome': 'vw_chamados_urgentes'},
        'ordem': "FIELD(prioridade, 'critica', 'alta'), data_abertura",
    },
    {
        'id': 'S4', 'nivel': 'simples',
        'titulo': 'Buscar equipamento por nome ou patrimônio',
        'descricao': 'Busca parcial: digite parte do nome ou do número de patrimônio.',
        'parametros': [{'nome': 'busca', 'rotulo': 'Texto a buscar', 'tipo': 'texto', 'padrao': 'note'}],
        'objeto': {'tipo': 'procedure', 'nome': 'sp_buscar_equipamento'},
    },
    {
        'id': 'S5', 'nivel': 'simples',
        'titulo': 'Equipamentos adquiridos em um período',
        'descricao': 'Mostra o que foi comprado entre duas datas.',
        'parametros': [{'nome': 'data_ini', 'rotulo': 'De', 'tipo': 'data', 'padrao': '2020-01-01'}, {'nome': 'data_fim', 'rotulo': 'Até', 'tipo': 'data', 'padrao': '2026-12-31'}],
        'objeto': {'tipo': 'procedure', 'nome': 'sp_equipamentos_por_periodo'},
    },
    {
        'id': 'S6', 'nivel': 'simples',
        'titulo': 'Quantidade de equipamentos por status',
        'descricao': 'Quantos itens estão disponíveis, em uso, em manutenção ou inativos.',
        'parametros': [],
        'objeto': {'tipo': 'view', 'nome': 'vw_equipamentos_por_status'},
        'ordem': 'total DESC',
        'grafico': {'tipo': 'doughnut', 'rotulo': 'status', 'valores': ['total']},
    },
    # ───────── INTERMEDIARIA ─────────
    {
        'id': 'I1', 'nivel': 'intermediaria',
        'titulo': 'Chamados com solicitante e equipamento',
        'descricao': 'Junta três tabelas para mostrar quem abriu o chamado e para qual equipamento.',
        'parametros': [P_STATUS],
        'objeto': {'tipo': 'procedure', 'nome': 'sp_chamados_com_solicitante'},
    },
    {
        'id': 'I2', 'nivel': 'intermediaria',
        'titulo': 'Chamados por equipamento',
        'descricao': 'Ranking dos equipamentos que mais dão problema (inclui os que nunca tiveram chamado).',
        'parametros': [],
        'objeto': {'tipo': 'view', 'nome': 'vw_chamados_por_equipamento'},
        'ordem': 'total_chamados DESC, equipamento',
        'grafico': {'tipo': 'bar', 'rotulo': 'equipamento', 'valores': ['total_chamados']},
    },
    {
        'id': 'I3', 'nivel': 'intermediaria',
        'titulo': 'Custo de manutenção por categoria',
        'descricao': 'Quanto cada categoria de equipamento já custou em manutenções.',
        'parametros': [],
        'objeto': {'tipo': 'view', 'nome': 'vw_custo_manutencao_por_categoria'},
        'ordem': 'custo_total DESC',
        'grafico': {'tipo': 'bar', 'rotulo': 'categoria', 'valores': ['custo_total']},
    },
    {
        'id': 'I4', 'nivel': 'intermediaria',
        'titulo': 'Equipamentos reincidentes',
        'descricao': 'Equipamentos com pelo menos N chamados (defina o mínimo).',
        'parametros': [{'nome': 'minimo', 'rotulo': 'Mínimo de chamados', 'tipo': 'numero', 'padrao': 2}],
        'objeto': {'tipo': 'procedure', 'nome': 'sp_equipamentos_reincidentes'},
        'grafico': {'tipo': 'bar', 'rotulo': 'nome', 'valores': ['total_chamados']},
    },
    {
        'id': 'I5', 'nivel': 'intermediaria',
        'titulo': 'Matriz prioridade × status dos chamados',
        'descricao': 'Tabela cruzada: quantos chamados de cada prioridade estão em cada situação.',
        'parametros': [],
        'objeto': {'tipo': 'view', 'nome': 'vw_matriz_prioridade_status'},
        'ordem': "FIELD(prioridade, 'critica', 'alta', 'media', 'baixa')",
        'grafico': {'tipo': 'bar', 'rotulo': 'prioridade', 'valores': ['abertos', 'em_analise', 'em_execucao', 'concluidos', 'cancelados']},
    },
    {
        'id': 'I6', 'nivel': 'intermediaria',
        'titulo': 'Manutenções com chamado, equipamento e solicitante',
        'descricao': 'Histórico completo de serviços, ligando quatro tabelas.',
        'parametros': [],
        'objeto': {'tipo': 'view', 'nome': 'vw_manutencoes_completas'},
        'ordem': 'data_inicio DESC, id_manutencao DESC',
    },
    {
        'id': 'I7', 'nivel': 'intermediaria',
        'titulo': 'Bens por setor da escola',
        'descricao': 'Quantos bens há em cada sala ou setor, por situação, e quantos têm chamado em andamento.',
        'parametros': [],
        'objeto': {'tipo': 'view', 'nome': 'vw_bens_por_setor'},
        'ordem': 'total_bens DESC, setor',
        'grafico': {'tipo': 'bar', 'rotulo': 'setor', 'valores': ['disponiveis', 'em_uso', 'em_manutencao', 'inativos']},
    },
    {
        'id': 'I8', 'nivel': 'intermediaria',
        'titulo': 'Manutenções e tempo médio de reparo',
        'descricao': 'Bens que já passaram por manutenção, com o tempo médio de reparo em dias e o custo total.',
        'parametros': [],
        'objeto': {'tipo': 'view', 'nome': 'vw_manutencao_tempo_medio_reparo'},
        'ordem': 'manutencoes_em_andamento DESC, dias_medio_reparo DESC, equipamento',
        'grafico': {'tipo': 'bar', 'rotulo': 'equipamento', 'valores': ['dias_medio_reparo']},
    },
    {
        'id': 'I9', 'nivel': 'intermediaria',
        'titulo': 'Patrimônio por responsável',
        'descricao': 'Quais bens cada professor ou funcionário acompanha, com o total de chamados e os que seguem em andamento.',
        'parametros': [],
        'objeto': {'tipo': 'view', 'nome': 'vw_patrimonio_por_responsavel'},
        'ordem': 'chamados DESC, responsavel',
    },
    # ───────── AVANCADA ─────────
    {
        'id': 'A1', 'nivel': 'avancada',
        'titulo': 'Equipamentos que nunca tiveram chamado',
        'descricao': 'Itens sem nenhum problema registrado.',
        'parametros': [],
        'objeto': {'tipo': 'view', 'nome': 'vw_equipamentos_sem_chamado'},
        'ordem': 'nome',
    },
    {
        'id': 'A2', 'nivel': 'avancada',
        'titulo': 'Equipamentos com custo acima da média',
        'descricao': 'Quem gastou mais em manutenção do que o custo médio por equipamento.',
        'parametros': [],
        'objeto': {'tipo': 'view', 'nome': 'vw_equipamentos_custo_acima_media'},
        'ordem': 'custo_total DESC',
        'grafico': {'tipo': 'bar', 'rotulo': 'nome', 'valores': ['custo_total']},
    },
    {
        'id': 'A3', 'nivel': 'avancada',
        'titulo': 'Ranking de usuários por chamados abertos',
        'descricao': 'Posição de cada usuário, com empates, e quantos chamados ainda estão em andamento.',
        'parametros': [],
        'objeto': {'tipo': 'view', 'nome': 'vw_ranking_usuarios_chamados'},
        'ordem': 'posicao, nome',
        'grafico': {'tipo': 'bar', 'rotulo': 'nome', 'valores': ['total_chamados', 'em_andamento']},
    },
    {
        'id': 'A4', 'nivel': 'avancada',
        'titulo': 'Tempo médio de resolução por prioridade',
        'descricao': 'Considera só chamados concluídos, medindo da abertura até a conclusão.',
        'parametros': [],
        'objeto': {'tipo': 'view', 'nome': 'vw_tempo_medio_resolucao'},
        'ordem': "FIELD(prioridade, 'critica', 'alta', 'media', 'baixa')",
        'grafico': {'tipo': 'bar', 'rotulo': 'prioridade', 'valores': ['dias_medios']},
    },
    {
        'id': 'A5', 'nivel': 'avancada',
        'titulo': 'Custo de manutenção acumulado mês a mês',
        'descricao': 'Total gasto em cada mês e o acumulado até aquele mês.',
        'parametros': [],
        'objeto': {'tipo': 'view', 'nome': 'vw_custo_acumulado_mensal'},
        'ordem': 'mes',
        'grafico': {'tipo': 'line', 'rotulo': 'mes', 'valores': ['custo_mes', 'custo_acumulado']},
    },
    {
        'id': 'A6', 'nivel': 'avancada',
        'titulo': 'Último chamado de cada equipamento',
        'descricao': 'Para cada equipamento, apenas o chamado mais recente.',
        'parametros': [],
        'objeto': {'tipo': 'view', 'nome': 'vw_ultimo_chamado_equipamento'},
        'ordem': 'data_abertura DESC',
    },
    {
        'id': 'A7', 'nivel': 'avancada',
        'titulo': 'Usuários que abriram chamados em várias categorias',
        'descricao': 'Quem reportou problemas em pelo menos N categorias diferentes de equipamento.',
        'parametros': [{'nome': 'minimo', 'rotulo': 'Mínimo de categorias', 'tipo': 'numero', 'padrao': 2}],
        'objeto': {'tipo': 'procedure', 'nome': 'sp_usuarios_multiplas_categorias'},
    },
    {
        'id': 'A8', 'nivel': 'avancada',
        'titulo': 'Resumo por equipamento usando funções armazenadas',
        'descricao': 'Chama as functions do banco (custo total, total de chamados e disponibilidade).',
        'parametros': [],
        'objeto': {'tipo': 'view', 'nome': 'vw_resumo_equipamentos_funcoes'},
        'ordem': 'custo_manutencao DESC, nome',
        'grafico': {'tipo': 'bar', 'rotulo': 'nome', 'valores': ['custo_manutencao']},
    },
    {
        'id': 'A9', 'nivel': 'avancada',
        'titulo': 'Linha do tempo de atividades (chamados + manutenções)',
        'descricao': 'Une dois tipos de evento numa única lista cronológica.',
        'parametros': [{'nome': 'limite', 'rotulo': 'Quantidade de linhas', 'tipo': 'numero', 'padrao': 10}],
        'objeto': {'tipo': 'procedure', 'nome': 'sp_linha_do_tempo'},
    },
    # ───────── PROCEDURE ─────────
    {
        'id': 'A10', 'nivel': 'avancada',
        'titulo': 'Auditoria do patrimônio',
        'descricao': 'Histórico de cadastros, transferências de sala, mudanças de status e exclusões dos bens.',
        'parametros': [],
        'objeto': {'tipo': 'view', 'nome': 'vw_auditoria_patrimonio'},
        'ordem': 'data_hora DESC, id_log DESC',
    },
    {
        'id': 'A11', 'nivel': 'avancada',
        'titulo': 'Bens críticos',
        'descricao': 'Bens ativos com chamado em andamento ou com custo de manutenção acima da média.',
        'parametros': [],
        'objeto': {'tipo': 'view', 'nome': 'vw_bens_criticos'},
        'ordem': 'chamados_ativos DESC, custo_manutencao DESC, equipamento',
    },
    {
        'id': 'P1', 'nivel': 'procedure',
        'titulo': 'Resumo do inventário',
        'descricao': 'Resumo do inventário por categoria: chamados, manutenções e custos de cada equipamento.',
        'parametros': [P_CATEGORIA],
        'objeto': {'tipo': 'procedure', 'nome': 'sp_resumo_equipamentos'},
    },
    {
        'id': 'P2', 'nivel': 'procedure',
        'titulo': 'Chamados detalhados',
        'descricao': 'Chamados com todos os detalhes (solicitante, equipamento, prioridade), filtrados por status.',
        'parametros': [P_STATUS],
        'objeto': {'tipo': 'procedure', 'nome': 'sp_chamados_detalhados'},
    },
    {
        'id': 'P3', 'nivel': 'procedure',
        'titulo': 'Desempenho dos usuários',
        'descricao': 'Quantos chamados cada usuário abriu e quantas movimentações fez.',
        'parametros': [],
        'objeto': {'tipo': 'procedure', 'nome': 'sp_desempenho_usuarios'},
    },
]

POR_ID = {c['id']: c for c in CONSULTAS}
