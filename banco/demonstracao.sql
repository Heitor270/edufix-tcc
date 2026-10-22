-- ============================================================
--  EduFix / inventario_escolar
--  Demonstração: executa cada objeto do banco (só leitura)
-- ============================================================
--  Ordem de criação do banco:
--    1) inventario_escolar.sql   (estrutura - APAGA e recria o banco)
--    2) functions.sql
--    3) views.sql
--    4) procedures.sql
--    5) triggers.sql
--  Este arquivo só faz consultas; pode rodar quantas vezes quiser.
-- ============================================================

USE inventario_escolar;


-- ------------------------------------------------------------
--  1) FUNCTIONS
-- ------------------------------------------------------------
SELECT fn_custo_total_manutencao(1)      AS custo_total_equip_1,
       fn_total_chamados_abertos(1)      AS chamados_abertos_usuario_1,
       fn_verificar_disponibilidade(1)   AS disponibilidade_equip_1,
       fn_tempo_resolucao_chamado(1)     AS horas_resolucao_chamado_1,
       fn_total_chamados_equipamento(1)  AS chamados_equip_1;

SELECT fn_usuario_eh_admin(1)            AS usuario_1_eh_admin,
       fn_manutencoes_em_andamento(1)    AS manutencoes_em_andamento_equip_1,
       fn_total_vinculos_usuario(1)      AS vinculos_usuario_1,
       fn_custo_total_chamado(1)         AS custo_chamado_1;


-- ------------------------------------------------------------
--  2) VIEWS - consultas simples
-- ------------------------------------------------------------
SELECT * FROM vw_equipamentos_disponiveis;      -- S1
SELECT * FROM vw_chamados_urgentes;             -- S3
SELECT * FROM vw_equipamentos_por_status;       -- S6

--  VIEWS - consultas intermediárias
SELECT * FROM vw_chamados_por_equipamento;      -- I2
SELECT * FROM vw_custo_manutencao_por_categoria;-- I3
SELECT * FROM vw_matriz_prioridade_status;      -- I5
SELECT * FROM vw_manutencoes_completas;         -- I6

--  VIEWS - consultas complexas
SELECT * FROM vw_equipamentos_sem_chamado;      -- A1
SELECT * FROM vw_equipamentos_custo_acima_media;-- A2
SELECT * FROM vw_ranking_usuarios_chamados;     -- A3 (CTE + RANK)
SELECT * FROM vw_tempo_medio_resolucao;         -- A4
SELECT * FROM vw_custo_acumulado_mensal;        -- A5 (CTE + janela)
SELECT * FROM vw_ultimo_chamado_equipamento;    -- A6 (ROW_NUMBER)
SELECT * FROM vw_resumo_equipamentos_funcoes;   -- A8 (usa as functions)


-- ------------------------------------------------------------
--  3) PROCEDURES de consulta (com parâmetro)
-- ------------------------------------------------------------
CALL sp_equipamentos_por_categoria('Informatica');          -- S2
CALL sp_buscar_equipamento('note');                         -- S4
CALL sp_equipamentos_por_periodo('2020-01-01', '2026-12-31');-- S5
CALL sp_chamados_com_solicitante('aberto');                 -- I1
CALL sp_equipamentos_reincidentes(2);                       -- I4
CALL sp_usuarios_multiplas_categorias(2);                   -- A7
CALL sp_linha_do_tempo(10);                                 -- A9

--  Procedures de relatório
CALL sp_resumo_equipamentos(NULL);
CALL sp_chamados_detalhados(NULL);
CALL sp_desempenho_usuarios();


-- ------------------------------------------------------------
--  4) PROCEDURES de operação e TRIGGERS (ALTERAM dados)
--     Descomente para demonstrar ao vivo. As procedures abrem e
--     confirmam a própria transação (COMMIT), então estas alterações
--     ficam gravadas. Os comandos de reversão estão no fim do bloco.
-- ------------------------------------------------------------
--   -- trg_chamado_data_fechamento: concluir preenche data_fechamento
--   CALL sp_alterar_status_chamado(1, 'concluido', 1, 'Teste de demonstração');
--   SELECT id_chamado, status, data_fechamento FROM chamado WHERE id_chamado = 1;
--   SELECT * FROM historico_status_chamado WHERE id_chamado = 1 ORDER BY id_historico DESC;
--
--   -- reabrir limpa data_fechamento
--   CALL sp_alterar_status_chamado(1, 'em_execucao', 1, 'Reaberto');
--   SELECT id_chamado, status, data_fechamento FROM chamado WHERE id_chamado = 1;
--
--   -- trg_usuario_normaliza_*: e-mail vira minúsculo e sem espaços
--   UPDATE usuario SET email = '  TESTE@Escola.COM ' WHERE id_usuario = 4;
--   SELECT id_usuario, email FROM usuario WHERE id_usuario = 4;
--
--   -- regras de integridade: ambos devolvem erro (45409 / 45404)
--   CALL sp_remover_usuario(1);
--   CALL sp_alterar_status_chamado(9999, 'aberto', 1, '');
--
--   -- reversão do que foi alterado acima
--   UPDATE usuario SET email = 'ana@gmail.com' WHERE id_usuario = 4;
--   DELETE FROM historico_status_chamado WHERE observacao IN ('Teste de demonstração', 'Reaberto');
