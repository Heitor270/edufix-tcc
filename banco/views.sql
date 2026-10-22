-- ============================================================
--  EduFix / inventario_escolar
--  Tópico 4 - Views (consultas sem parâmetro)
-- ============================================================
--  Cada view abaixo é uma consulta do sistema (Consultas > Simples,
--  Intermediárias e Complexas). O site apenas faz: SELECT * FROM <view>.
--  Requer MySQL 8.0+ (A3, A5 e A6 usam CTE / funções de janela).
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
