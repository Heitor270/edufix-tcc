-- ============================================================
--  EduFix / inventario_escolar
--  Tópico 4 - Views (consultas sem parâmetro)
-- ============================================================
--  Cada view abaixo é uma consulta do sistema (Consultas > Simples,
--  Intermediárias e Complexas). O site apenas faz: SELECT * FROM <view>.
--  Requer MySQL 8.0+ (A3, A5 e A6 usam CTE / funções de janela).
--
--  ORDEM DE EXECUÇÃO dos scripts (cada um depende do anterior):
--    functions.sql -> procedures.sql -> triggers.sql -> views.sql
--  (as views de patrimônio usam as functions e a tabela log_patrimonio,
--   criada pelo triggers.sql)
-- ============================================================
 
USE inventario_escolar;
 
 
-- ------------------------------------------------------------
--  CONSULTAS SIMPLES
-- ------------------------------------------------------------
 
-- S1 - Equipamentos disponíveis (SELECT, WHERE, ORDER BY)
DROP VIEW IF EXISTS vw_equipamentos_disponiveis;
CREATE VIEW vw_equipamentos_disponiveis AS
SELECT id_equipamento, nome, categoria, localizacao, numero_patrimonio
FROM equipamento
WHERE status = 'disponivel'
ORDER BY nome;
 
 
-- S3 - Chamados urgentes ainda em andamento (IN, AND, FIELD)
DROP VIEW IF EXISTS vw_chamados_urgentes;
CREATE VIEW vw_chamados_urgentes AS
SELECT id_chamado, prioridade, status, descricao_problema, data_abertura
FROM chamado
WHERE prioridade IN ('alta', 'critica')
  AND status IN ('aberto', 'em_analise', 'em_execucao')
ORDER BY FIELD(prioridade, 'critica', 'alta'), data_abertura;
 
 
-- S6 - Quantidade de equipamentos por status (COUNT, GROUP BY)
DROP VIEW IF EXISTS vw_equipamentos_por_status;
CREATE VIEW vw_equipamentos_por_status AS
SELECT status, COUNT(*) AS total
FROM equipamento
GROUP BY status
ORDER BY total DESC;
 
 
-- ------------------------------------------------------------
--  CONSULTAS INTERMEDIÁRIAS
-- ------------------------------------------------------------
 
-- I2 - Chamados por equipamento (LEFT JOIN, COUNT, GROUP BY)
DROP VIEW IF EXISTS vw_chamados_por_equipamento;
CREATE VIEW vw_chamados_por_equipamento AS
SELECT e.nome AS equipamento, COUNT(c.id_chamado) AS total_chamados
FROM equipamento e
LEFT JOIN chamado c ON c.id_equipamento = e.id_equipamento
GROUP BY e.id_equipamento, e.nome
ORDER BY total_chamados DESC, e.nome;
 
 
-- I3 - Custo de manutenção por categoria (INNER JOIN, SUM, AVG, COUNT)
DROP VIEW IF EXISTS vw_custo_manutencao_por_categoria;
CREATE VIEW vw_custo_manutencao_por_categoria AS
SELECT e.categoria,
       COUNT(m.id_manutencao) AS qtd_manutencoes,
       SUM(m.custo) AS custo_total,
       ROUND(AVG(m.custo), 2) AS custo_medio
FROM manutencao m
INNER JOIN equipamento e ON e.id_equipamento = m.id_equipamento
GROUP BY e.categoria
ORDER BY custo_total DESC;
 
 
-- I5 - Matriz prioridade x status (agregação condicional SUM(CASE WHEN))
DROP VIEW IF EXISTS vw_matriz_prioridade_status;
CREATE VIEW vw_matriz_prioridade_status AS
SELECT prioridade,
       SUM(CASE WHEN status = 'aberto'      THEN 1 ELSE 0 END) AS abertos,
       SUM(CASE WHEN status = 'em_analise'  THEN 1 ELSE 0 END) AS em_analise,
       SUM(CASE WHEN status = 'em_execucao' THEN 1 ELSE 0 END) AS em_execucao,
       SUM(CASE WHEN status = 'concluido'   THEN 1 ELSE 0 END) AS concluidos,
       SUM(CASE WHEN status = 'cancelado'   THEN 1 ELSE 0 END) AS cancelados
FROM chamado
GROUP BY prioridade
ORDER BY FIELD(prioridade, 'critica', 'alta', 'media', 'baixa');
 
 
-- I6 - Manutenções com chamado, equipamento e solicitante (INNER JOIN em 4 tabelas)
DROP VIEW IF EXISTS vw_manutencoes_completas;
CREATE VIEW vw_manutencoes_completas AS
SELECT m.id_manutencao, e.nome AS equipamento, c.descricao_problema,
       u.nome AS solicitante, m.tecnico_responsavel,
       m.data_inicio, m.data_fim, m.custo
FROM manutencao m
INNER JOIN equipamento e ON e.id_equipamento = m.id_equipamento
INNER JOIN chamado c     ON c.id_chamado     = m.id_chamado
INNER JOIN usuario u     ON u.id_usuario     = c.id_usuario
ORDER BY m.data_inicio DESC;
 
 
-- ------------------------------------------------------------
--  CONSULTAS COMPLEXAS
-- ------------------------------------------------------------
 
-- A1 - Equipamentos que nunca tiveram chamado (NOT EXISTS, subconsulta correlacionada)
DROP VIEW IF EXISTS vw_equipamentos_sem_chamado;
CREATE VIEW vw_equipamentos_sem_chamado AS
SELECT e.nome, e.numero_patrimonio, e.categoria
FROM equipamento e
WHERE NOT EXISTS (
    SELECT 1
    FROM chamado c
    WHERE c.id_equipamento = e.id_equipamento
)
ORDER BY e.nome;
 
 
-- A2 - Equipamentos com custo acima da média (HAVING com subconsulta + tabela derivada)
DROP VIEW IF EXISTS vw_equipamentos_custo_acima_media;
CREATE VIEW vw_equipamentos_custo_acima_media AS
SELECT e.nome, e.categoria, SUM(m.custo) AS custo_total
FROM equipamento e
INNER JOIN manutencao m ON m.id_equipamento = e.id_equipamento
GROUP BY e.id_equipamento, e.nome, e.categoria
HAVING SUM(m.custo) > (
    SELECT AVG(t.total)
    FROM (
        SELECT SUM(custo) AS total
        FROM manutencao
        GROUP BY id_equipamento
    ) AS t
)
ORDER BY custo_total DESC;
 
 
-- A3 - Ranking de usuários por chamados (CTE + RANK() OVER)
DROP VIEW IF EXISTS vw_ranking_usuarios_chamados;
CREATE VIEW vw_ranking_usuarios_chamados AS
WITH resumo AS (
    SELECT u.id_usuario, u.nome,
           COUNT(c.id_chamado) AS total_chamados,
           SUM(CASE WHEN c.status IN ('aberto', 'em_analise', 'em_execucao')
                    THEN 1 ELSE 0 END) AS em_andamento
    FROM usuario u
    LEFT JOIN chamado c ON c.id_usuario = u.id_usuario
    GROUP BY u.id_usuario, u.nome
)
SELECT RANK() OVER (ORDER BY total_chamados DESC) AS posicao,
       nome, total_chamados, em_andamento
FROM resumo
ORDER BY posicao, nome;
 
 
-- A4 - Tempo médio de resolução por prioridade (TIMESTAMPDIFF, AVG)
DROP VIEW IF EXISTS vw_tempo_medio_resolucao;
CREATE VIEW vw_tempo_medio_resolucao AS
SELECT prioridade,
       COUNT(*) AS concluidos,
       ROUND(AVG(TIMESTAMPDIFF(HOUR, data_abertura, data_fechamento)), 1) AS horas_medias,
       ROUND(AVG(TIMESTAMPDIFF(HOUR, data_abertura, data_fechamento)) / 24, 1) AS dias_medios
FROM chamado
WHERE status = 'concluido'
  AND data_fechamento IS NOT NULL
GROUP BY prioridade
ORDER BY FIELD(prioridade, 'critica', 'alta', 'media', 'baixa');
 
 
-- A5 - Custo de manutenção acumulado mês a mês (CTE + SUM() OVER)
DROP VIEW IF EXISTS vw_custo_acumulado_mensal;
CREATE VIEW vw_custo_acumulado_mensal AS
WITH mensal AS (
    SELECT DATE_FORMAT(data_inicio, '%Y-%m') AS mes,
           SUM(custo) AS custo_mes
    FROM manutencao
    GROUP BY DATE_FORMAT(data_inicio, '%Y-%m')
)
SELECT mes, custo_mes,
       SUM(custo_mes) OVER (ORDER BY mes) AS custo_acumulado
FROM mensal
ORDER BY mes;
 
 
-- A6 - Último chamado de cada equipamento (ROW_NUMBER() OVER PARTITION BY)
DROP VIEW IF EXISTS vw_ultimo_chamado_equipamento;
CREATE VIEW vw_ultimo_chamado_equipamento AS
SELECT t.equipamento, t.prioridade, t.status, t.data_abertura
FROM (
    SELECT e.nome AS equipamento, c.prioridade, c.status, c.data_abertura,
           ROW_NUMBER() OVER (PARTITION BY c.id_equipamento
                              ORDER BY c.data_abertura DESC) AS rn
    FROM chamado c
    INNER JOIN equipamento e ON e.id_equipamento = c.id_equipamento
) AS t
WHERE t.rn = 1
ORDER BY t.data_abertura DESC;
 
 
-- A8 - Resumo por equipamento usando as FUNCTIONS armazenadas
DROP VIEW IF EXISTS vw_resumo_equipamentos_funcoes;
CREATE VIEW vw_resumo_equipamentos_funcoes AS
SELECT e.nome,
       fn_total_chamados_equipamento(e.id_equipamento) AS chamados,
       fn_custo_total_manutencao(e.id_equipamento)     AS custo_manutencao,
       fn_verificar_disponibilidade(e.id_equipamento)  AS disponibilidade
FROM equipamento e
ORDER BY custo_manutencao DESC, e.nome;
 
 
-- ============================================================
--  VIEWS DO PATRIMÔNIO ESCOLAR (trabalho de Banco de Dados II)
--  Usam as functions, a tabela de auditoria (log_patrimonio) e,
--  em um caso, outra view (view sobre view).
-- ============================================================
 
-- V1 - Relatório de bens por setor da escola.
-- Considera "setor" a localização do bem (sala, laboratório, secretaria...).
-- Mostra a distribuição por status, quantos bens têm chamado em andamento
-- (function fn_chamados_ativos_equipamento) e o percentual em manutenção.
DROP VIEW IF EXISTS vw_bens_por_setor;
CREATE VIEW vw_bens_por_setor AS
SELECT t.setor,
       COUNT(*) AS total_bens,
       SUM(CASE WHEN t.status = 'disponivel' THEN 1 ELSE 0 END) AS disponiveis,
       SUM(CASE WHEN t.status = 'em_uso' THEN 1 ELSE 0 END) AS em_uso,
       SUM(CASE WHEN t.status = 'em_manutencao' THEN 1 ELSE 0 END) AS em_manutencao,
       SUM(CASE WHEN t.status = 'inativo' THEN 1 ELSE 0 END) AS inativos,
       SUM(CASE WHEN fn_chamados_ativos_equipamento(t.id_equipamento) > 0
                THEN 1 ELSE 0 END) AS com_chamado_ativo,
       ROUND(100 * SUM(CASE WHEN t.status = 'em_manutencao' THEN 1 ELSE 0 END)
                 / COUNT(*), 1) AS pct_em_manutencao
FROM (SELECT id_equipamento, status,
             COALESCE(localizacao, 'Sem setor definido') AS setor
      FROM equipamento) AS t
GROUP BY t.setor
ORDER BY total_bens DESC, setor;
 
 
-- V2 - Patrimônio com manutenção e tempo médio de reparo.
-- Para cada bem que já teve manutenção: quantas foram concluídas, quantas
-- estão em andamento (fn_manutencoes_em_andamento), o tempo médio de reparo
-- em dias (início -> fim), há quantos dias está parado na manutenção atual
-- e o custo total (fn_custo_total_manutencao).
DROP VIEW IF EXISTS vw_manutencao_tempo_medio_reparo;
CREATE VIEW vw_manutencao_tempo_medio_reparo AS
SELECT e.id_equipamento,
       e.nome AS equipamento,
       e.categoria,
       COALESCE(e.localizacao, 'Sem setor definido') AS setor,
       e.status AS status_atual,
       COUNT(CASE WHEN m.data_fim IS NOT NULL THEN 1 END) AS manutencoes_concluidas,
       fn_manutencoes_em_andamento(e.id_equipamento) AS manutencoes_em_andamento,
       ROUND(AVG(CASE WHEN m.data_fim IS NOT NULL
                      THEN DATEDIFF(m.data_fim, m.data_inicio) END), 1) AS dias_medio_reparo,
       MAX(CASE WHEN m.data_fim IS NULL
                THEN DATEDIFF(CURDATE(), m.data_inicio) END) AS dias_parado_atual,
       fn_custo_total_manutencao(e.id_equipamento) AS custo_total
FROM equipamento e
INNER JOIN manutencao m ON m.id_equipamento = e.id_equipamento
GROUP BY e.id_equipamento, e.nome, e.categoria, e.localizacao, e.status
ORDER BY manutencoes_em_andamento DESC, dias_medio_reparo DESC, equipamento;
 
 
-- V3 - Patrimônio vinculado a cada responsável (professor ou funcionário).
-- No sistema, o responsável por um bem é quem abre os chamados sobre ele.
-- Lista, por usuário ativo, os bens com que se relacionou (GROUP_CONCAT),
-- quantos chamados abriu, quantos seguem em andamento e o último chamado.
DROP VIEW IF EXISTS vw_patrimonio_por_responsavel;
CREATE VIEW vw_patrimonio_por_responsavel AS
SELECT u.id_usuario,
       u.nome AS responsavel,
       u.tipo_usuario AS perfil,
       COUNT(DISTINCT c.id_equipamento) AS bens_vinculados,
       GROUP_CONCAT(DISTINCT e.nome ORDER BY e.nome SEPARATOR ', ') AS bens,
       COUNT(c.id_chamado) AS chamados,
       SUM(CASE WHEN c.status IN ('aberto', 'em_analise', 'em_execucao')
                THEN 1 ELSE 0 END) AS em_andamento,
       MAX(c.data_abertura) AS ultimo_chamado
FROM usuario u
INNER JOIN chamado c ON c.id_usuario = u.id_usuario
LEFT JOIN equipamento e ON e.id_equipamento = c.id_equipamento
WHERE u.ativo = TRUE
GROUP BY u.id_usuario, u.nome, u.tipo_usuario
ORDER BY chamados DESC, responsavel;
 
 
-- V4 - Auditoria do patrimônio em linguagem legível.
-- Lê a tabela log_patrimonio (alimentada pelas triggers) e traduz cada
-- registro em uma frase. O LEFT JOIN mostra também os bens já excluídos.
DROP VIEW IF EXISTS vw_auditoria_patrimonio;
CREATE VIEW vw_auditoria_patrimonio AS
SELECT l.id_log,
       l.data_hora,
       COALESCE(e.nome, l.nome_equipamento) AS equipamento,
       CASE WHEN e.id_equipamento IS NULL THEN 'excluído' ELSE 'ativo no cadastro' END
                                                                          AS situacao_cadastro,
       l.acao,
       CASE l.acao
            WHEN 'CADASTRO' THEN CONCAT('Cadastrado em ', COALESCE(l.valor_novo, '-'))
            WHEN 'TRANSFERENCIA' THEN CONCAT('Transferido de ', COALESCE(l.valor_anterior, '-'),
                                                   ' para ', COALESCE(l.valor_novo, '-'))
            WHEN 'MUDANCA_STATUS' THEN CONCAT('Status: ', l.valor_anterior, ' -> ', l.valor_novo)
            WHEN 'MUDANCA_CONSERVACAO' THEN CONCAT('Conservação: ', l.valor_anterior, ' -> ', l.valor_novo)
            ELSE CONCAT('Excluído (último status: ', COALESCE(l.valor_anterior, '-'), ')')
       END AS descricao,
       l.usuario_banco
FROM log_patrimonio l
LEFT JOIN equipamento e ON e.id_equipamento = l.id_equipamento
ORDER BY l.data_hora DESC, l.id_log DESC;
 
 
-- V5 - Bens críticos (VIEW SOBRE VIEW).
-- Bens ativos que têm chamado em andamento OU custo de manutenção acima da
-- média; o segundo critério vem da view vw_equipamentos_custo_acima_media.
DROP VIEW IF EXISTS vw_bens_criticos;
CREATE VIEW vw_bens_criticos AS
SELECT e.id_equipamento,
       e.nome AS equipamento,
       COALESCE(e.localizacao, 'Sem setor definido') AS setor,
       e.status,
       fn_chamados_ativos_equipamento(e.id_equipamento) AS chamados_ativos,
       fn_total_chamados_equipamento(e.id_equipamento) AS chamados_total,
       fn_custo_total_manutencao(e.id_equipamento) AS custo_manutencao,
       CASE WHEN a.nome IS NOT NULL THEN 'Sim' ELSE 'Não' END AS custo_acima_da_media
FROM equipamento e
LEFT JOIN vw_equipamentos_custo_acima_media a
       ON a.nome = e.nome AND a.categoria <=> e.categoria
WHERE e.status <> 'inativo'
  AND (fn_chamados_ativos_equipamento(e.id_equipamento) > 0 OR a.nome IS NOT NULL)
ORDER BY chamados_ativos DESC, custo_manutencao DESC, equipamento;
 
 
 
-- ============================================================
--  VIEWS DA v3 (classes Setor, Categoria, movimentação, SLA e perfis)
-- ============================================================
 
-- V6 - Resumo de cada setor (classe Setor: listarBens / contarBens).
-- Mostra TODOS os setores cadastrados, inclusive os vazios.
DROP VIEW IF EXISTS vw_setores_resumo;
CREATE VIEW vw_setores_resumo AS
SELECT s.id_setor,
       s.nome AS setor,
       COUNT(e.id_equipamento) AS total_bens,
       COALESCE(SUM(e.status = 'disponivel'), 0)     AS disponiveis,
       COALESCE(SUM(e.status = 'em_uso'), 0)         AS em_uso,
       COALESCE(SUM(e.status = 'em_manutencao'), 0)  AS em_manutencao,
       COALESCE(SUM(e.status = 'inativo'), 0)        AS inativos,
       COALESCE(SUM(fn_equipamento_em_movimentacao(e.id_equipamento)), 0) AS saindo_do_setor,
       (SELECT COUNT(*) FROM movimentacao_equipamento m
         WHERE m.id_setor_destino = s.id_setor AND m.situacao = 'em_transito') AS chegando_ao_setor
FROM setor s
LEFT JOIN equipamento e ON e.id_setor = s.id_setor
GROUP BY s.id_setor, s.nome
ORDER BY total_bens DESC, setor;
 
 
-- V7 - Resumo de cada categoria (classe Categoria: listarBens).
DROP VIEW IF EXISTS vw_categorias_resumo;
CREATE VIEW vw_categorias_resumo AS
SELECT c.id_categoria,
       c.nome AS categoria,
       COUNT(e.id_equipamento) AS total_bens,
       COALESCE(SUM(e.status = 'inativo'), 0) AS inativos,
       ROUND(AVG(fn_nivel_conservacao(e.estado_conservacao)), 2) AS conservacao_media_0_a_4,
       COALESCE(SUM(fn_custo_total_manutencao(e.id_equipamento)), 0) AS custo_manutencao
FROM categoria c
LEFT JOIN equipamento e ON e.id_categoria = c.id_categoria
GROUP BY c.id_categoria, c.nome
ORDER BY total_bens DESC, categoria;
 
 
-- V8 - Bens em movimentação agora (propriedade em_movimentacao da classe Equipamento).
DROP VIEW IF EXISTS vw_equipamentos_em_movimentacao;
CREATE VIEW vw_equipamentos_em_movimentacao AS
SELECT m.id_movimentacao,
       e.id_equipamento,
       e.nome AS equipamento,
       e.numero_patrimonio,
       so.nome AS setor_origem,
       sd.nome AS setor_destino,
       u.nome AS responsavel,
       m.data_inicio,
       TIMESTAMPDIFF(HOUR, m.data_inicio, NOW()) AS horas_em_transito,
       m.observacao
FROM movimentacao_equipamento m
INNER JOIN equipamento e ON e.id_equipamento = m.id_equipamento
LEFT JOIN setor so       ON so.id_setor = m.id_setor_origem
INNER JOIN setor sd      ON sd.id_setor = m.id_setor_destino
INNER JOIN usuario u     ON u.id_usuario = m.id_usuario
WHERE m.situacao = 'em_transito'
ORDER BY m.data_inicio;
 
 
-- V9 - Histórico completo de movimentações (concluídas, canceladas e em trânsito).
DROP VIEW IF EXISTS vw_movimentacoes;
CREATE VIEW vw_movimentacoes AS
SELECT m.id_movimentacao,
       e.nome AS equipamento,
       so.nome AS setor_origem,
       sd.nome AS setor_destino,
       m.situacao,
       u.nome AS responsavel,
       m.data_inicio,
       m.data_conclusao,
       ROUND(TIMESTAMPDIFF(MINUTE, m.data_inicio, COALESCE(m.data_conclusao, NOW())) / 60, 1) AS horas
FROM movimentacao_equipamento m
INNER JOIN equipamento e ON e.id_equipamento = m.id_equipamento
LEFT JOIN setor so       ON so.id_setor = m.id_setor_origem
INNER JOIN setor sd      ON sd.id_setor = m.id_setor_destino
INNER JOIN usuario u     ON u.id_usuario = m.id_usuario
ORDER BY m.data_inicio DESC, m.id_movimentacao DESC;
 
 
-- V10 - SLA dos chamados: prazo da prioridade, horas decorridas e se estourou
-- (funções fn_sla_horas e fn_chamado_sla_estourado).
DROP VIEW IF EXISTS vw_chamados_sla;
CREATE VIEW vw_chamados_sla AS
SELECT c.id_chamado,
       u.nome AS solicitante,
       e.nome AS equipamento,
       c.prioridade,
       c.status,
       fn_sla_horas(c.prioridade) AS prazo_horas,
       fn_horas_chamado(c.id_chamado) AS horas_decorridas,
       fn_chamado_sla_estourado(c.id_chamado) AS sla_estourado,
       ROUND(fn_horas_chamado(c.id_chamado) - fn_sla_horas(c.prioridade), 1) AS horas_de_atraso
FROM chamado c
INNER JOIN usuario u ON u.id_usuario = c.id_usuario
LEFT JOIN equipamento e ON e.id_equipamento = c.id_equipamento
ORDER BY sla_estourado DESC, FIELD(c.prioridade, 'critica', 'alta', 'media', 'baixa'), c.data_abertura;
 
 
-- V11 - Histórico de status dos chamados com quem mudou e quanto tempo o chamado
-- ficou no status anterior (função de janela LAG).
DROP VIEW IF EXISTS vw_historico_chamados;
CREATE VIEW vw_historico_chamados AS
SELECT h.id_chamado,
       h.id_historico,
       COALESCE(h.status_anterior, '(abertura)') AS de_status,
       h.status_novo AS para_status,
       u.nome AS alterado_por,
       h.data_alteracao,
       ROUND(TIMESTAMPDIFF(MINUTE,
             LAG(h.data_alteracao) OVER (PARTITION BY h.id_chamado ORDER BY h.data_alteracao, h.id_historico),
             h.data_alteracao) / 60, 1) AS horas_no_status_anterior,
       h.observacao
FROM historico_status_chamado h
INNER JOIN usuario u ON u.id_usuario = h.id_usuario
ORDER BY h.id_chamado, h.data_alteracao, h.id_historico;
 
 
-- V12 - Manutenções em andamento, há quantos dias e com o custo até agora.
DROP VIEW IF EXISTS vw_manutencoes_em_andamento;
CREATE VIEW vw_manutencoes_em_andamento AS
SELECT m.id_manutencao,
       e.nome AS equipamento,
       s.nome AS setor,
       c.id_chamado,
       c.status AS status_chamado,
       m.tecnico_responsavel,
       m.data_inicio,
       DATEDIFF(CURDATE(), m.data_inicio) AS dias_em_andamento,
       fn_custo_manutencao_total(m.id_manutencao, 0) AS custo_ate_agora
FROM manutencao m
INNER JOIN chamado c     ON c.id_chamado = m.id_chamado
INNER JOIN equipamento e ON e.id_equipamento = m.id_equipamento
LEFT JOIN setor s        ON s.id_setor = e.id_setor
WHERE m.data_fim IS NULL
ORDER BY dias_em_andamento DESC, equipamento;
 
 
-- V13 - Ranking de técnicos: quantos serviços, quantos concluídos, tempo médio e custo.
-- (CTE + RANK() OVER)
DROP VIEW IF EXISTS vw_ranking_tecnicos;
CREATE VIEW vw_ranking_tecnicos AS
WITH base AS (
    SELECT COALESCE(NULLIF(tecnico_responsavel, ''), 'Não informado') AS tecnico,
           data_inicio, data_fim, custo
    FROM manutencao
),
por_tecnico AS (
    SELECT b.tecnico,
           COUNT(*) AS servicos,
           SUM(b.data_fim IS NOT NULL) AS concluidos,
           ROUND(AVG(CASE WHEN b.data_fim IS NOT NULL
                          THEN DATEDIFF(b.data_fim, b.data_inicio) + 1 END), 1) AS dias_medios,
           SUM(b.custo) AS custo_total
    FROM base b
    GROUP BY b.tecnico
)
SELECT RANK() OVER (ORDER BY servicos DESC, concluidos DESC) AS posicao,
       tecnico, servicos, concluidos, dias_medios, custo_total
FROM por_tecnico
ORDER BY posicao, tecnico;
 
 
-- V14 - Estado de conservação por categoria (tabela cruzada).
DROP VIEW IF EXISTS vw_conservacao_por_categoria;
CREATE VIEW vw_conservacao_por_categoria AS
SELECT COALESCE(c.nome, e.categoria, 'Sem categoria') AS categoria,
       SUM(e.estado_conservacao = 'otimo')        AS otimo,
       SUM(e.estado_conservacao = 'bom')          AS bom,
       SUM(e.estado_conservacao = 'regular')      AS regular,
       SUM(e.estado_conservacao = 'ruim')         AS ruim,
       SUM(e.estado_conservacao = 'inutilizavel') AS inutilizavel,
       COUNT(*) AS total
FROM equipamento e
LEFT JOIN categoria c ON c.id_categoria = e.id_categoria
GROUP BY COALESCE(c.nome, e.categoria, 'Sem categoria')
ORDER BY total DESC, categoria;
 
 
-- V15 - Perfis de acesso: cada administrador com o que o nível e a lista de
-- permissões realmente liberam (função fn_admin_tem_permissao).
DROP VIEW IF EXISTS vw_perfis_de_acesso;
CREATE VIEW vw_perfis_de_acesso AS
SELECT u.id_usuario,
       u.nome,
       u.ativo,
       a.nivel_acesso,
       a.permissoes,
       fn_admin_tem_permissao(u.id_usuario, 'gerenciar_chamados')   AS chamados,
       fn_admin_tem_permissao(u.id_usuario, 'gerenciar_patrimonio') AS patrimonio,
       fn_admin_tem_permissao(u.id_usuario, 'emitir_relatorios')    AS relatorios,
       fn_admin_tem_permissao(u.id_usuario, 'gerenciar_usuarios')   AS usuarios
FROM usuario u
INNER JOIN admin a ON a.id_admin = u.id_usuario
ORDER BY a.nivel_acesso DESC, u.nome;
 
 
-- V16 - Alertas operacionais (UNION ALL): chamado crítico em andamento, SLA estourado,
-- bem reincidente (3+ chamados), manutenção parada há muito tempo e bem em trânsito há mais de 24h.
DROP VIEW IF EXISTS vw_alertas_operacionais;
CREATE VIEW vw_alertas_operacionais AS
SELECT 'CRITICO' AS tipo,
       CONCAT('Chamado #', c.id_chamado, ' crítico em andamento: ', COALESCE(e.nome, 'sem equipamento')) AS alerta
FROM chamado c
LEFT JOIN equipamento e ON e.id_equipamento = c.id_equipamento
WHERE c.prioridade = 'critica' AND c.status IN ('aberto', 'em_analise', 'em_execucao')
UNION ALL
SELECT 'SLA',
       CONCAT('Chamado #', c.id_chamado, ' passou do prazo de ', fn_sla_horas(c.prioridade), 'h')
FROM chamado c
WHERE c.status IN ('aberto', 'em_analise', 'em_execucao')
  AND fn_chamado_sla_estourado(c.id_chamado) = 1
UNION ALL
SELECT 'REINCIDENCIA',
       CONCAT(e.nome, ' tem ', COUNT(*), ' chamados: avaliar substituição')
FROM chamado c
INNER JOIN equipamento e ON e.id_equipamento = c.id_equipamento
GROUP BY e.id_equipamento, e.nome
HAVING COUNT(*) >= 3
UNION ALL
SELECT 'MANUTENCAO PARADA',
       CONCAT('Manutenção #', m.id_manutencao, ' de ', e.nome, ' aberta há ',
              DATEDIFF(CURDATE(), m.data_inicio), ' dias')
FROM manutencao m
INNER JOIN equipamento e ON e.id_equipamento = m.id_equipamento
WHERE m.data_fim IS NULL AND DATEDIFF(CURDATE(), m.data_inicio) > 7
UNION ALL
SELECT 'EM TRANSITO',
       CONCAT(e.nome, ' em trânsito há ', TIMESTAMPDIFF(HOUR, m.data_inicio, NOW()), 'h')
FROM movimentacao_equipamento m
INNER JOIN equipamento e ON e.id_equipamento = m.id_equipamento
WHERE m.situacao = 'em_transito' AND TIMESTAMPDIFF(HOUR, m.data_inicio, NOW()) > 24;
 
 
-- V17 - Verificação de integridade do modelo: lista registros que contrariam as regras
-- (deve vir VAZIA num banco saudável; útil para a demonstração e para dados antigos).
DROP VIEW IF EXISTS vw_inconsistencias;
CREATE VIEW vw_inconsistencias AS
SELECT 'Bem sem setor' AS problema, e.nome AS item, CAST(e.id_equipamento AS CHAR) AS referencia
FROM equipamento e
WHERE e.id_setor IS NULL AND e.localizacao IS NOT NULL
UNION ALL
SELECT 'Bem sem categoria', e.nome, CAST(e.id_equipamento AS CHAR)
FROM equipamento e
WHERE e.id_categoria IS NULL
UNION ALL
SELECT 'Bem em_manutencao sem manutenção aberta', e.nome, CAST(e.id_equipamento AS CHAR)
FROM equipamento e
WHERE e.status = 'em_manutencao' AND fn_manutencoes_em_andamento(e.id_equipamento) = 0
UNION ALL
SELECT 'Manutenção aberta mas bem não está em_manutencao', e.nome, CAST(e.id_equipamento AS CHAR)
FROM equipamento e
WHERE e.status <> 'em_manutencao' AND fn_manutencoes_em_andamento(e.id_equipamento) > 0
UNION ALL
SELECT 'Chamado em andamento em bem inativo', CONCAT('Chamado #', c.id_chamado), CAST(c.id_chamado AS CHAR)
FROM chamado c
INNER JOIN equipamento e ON e.id_equipamento = c.id_equipamento
WHERE c.status IN ('aberto', 'em_analise', 'em_execucao') AND e.status = 'inativo'
UNION ALL
SELECT 'Manutenção aberta em chamado encerrado', CONCAT('Manutenção #', m.id_manutencao), CAST(m.id_manutencao AS CHAR)
FROM manutencao m
INNER JOIN chamado c ON c.id_chamado = m.id_chamado
WHERE m.data_fim IS NULL AND c.status IN ('concluido', 'cancelado')
UNION ALL
SELECT 'Manutenção de equipamento diferente do chamado', CONCAT('Manutenção #', m.id_manutencao), CAST(m.id_manutencao AS CHAR)
FROM manutencao m
INNER JOIN chamado c ON c.id_chamado = m.id_chamado
WHERE c.id_equipamento IS NULL OR c.id_equipamento <> m.id_equipamento
UNION ALL
SELECT 'Chamado sem histórico', CONCAT('Chamado #', c.id_chamado), CAST(c.id_chamado AS CHAR)
FROM chamado c
WHERE NOT EXISTS (SELECT 1 FROM historico_status_chamado h WHERE h.id_chamado = c.id_chamado);