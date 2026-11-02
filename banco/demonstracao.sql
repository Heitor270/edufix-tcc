-- ============================================================
--  EduFix / inventario_escolar
--  Demonstração: executa cada objeto do banco (só leitura)
-- ============================================================
--  Ordem de criação do banco (v3):
--    1) inventario_escolar.sql   (estrutura - APAGA e recria o banco)
--       (banco que já tem dados: use migracao_v3.sql no lugar deste)
--    2) functions.sql
--    3) views.sql
--    4) procedures.sql
--    5) triggers.sql
--  As seções 1 a 4 só fazem consultas; pode rodar quantas vezes quiser.
--  As seções 5 e 6 alteram dados e vêm comentadas.
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

-- Functions da versão 3
SELECT fn_validar_cpf('529.982.247-25')  AS cpf_valido,
       fn_validar_cpf('111.111.111-11')  AS cpf_invalido,
       fn_validar_email('ana@gmail.com') AS email_valido,
       fn_sla_horas('critica')           AS sla_critica_h,
       fn_sla_horas('baixa')             AS sla_baixa_h,
       fn_horas_chamado(1)               AS horas_chamado_1,
       fn_chamado_sla_estourado(1)       AS sla_estourado_chamado_1;

SELECT fn_transicao_status_valida('aberto', 'em_analise')   AS aberto_para_analise,
       fn_transicao_status_valida('concluido', 'em_analise') AS concluido_para_analise,
       fn_nivel_conservacao('bom')                           AS nivel_bom,
       fn_classificar_prioridade('equipamento pegando fogo', NULL) AS prioridade_sugerida,
       fn_nome_setor('Laboratório 1 - bancada 2')            AS setor_da_localizacao,
       fn_equipamento_em_movimentacao(1)                     AS equip_1_em_movimentacao,
       fn_total_bens_setor(1, NULL)                          AS bens_no_setor_1,
       fn_idade_equipamento_anos(1)                          AS idade_equip_1,
       fn_manutencoes_em_andamento_chamado(1)                AS manut_andamento_chamado_1,
       fn_custo_manutencao_total(1, 50.00)                   AS custo_manut_1_com_mao_de_obra,
       fn_pode_melhorar_conservacao(1, 'otimo')              AS pode_ir_para_otimo,
       fn_admin_tem_permissao(1, 'gerenciar_chamados')       AS admin_1_gerencia_chamados;

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

--  VIEWS DO PATRIMÔNIO (trabalho de Banco II)
SELECT * FROM vw_bens_por_setor;                -- I7 (bens por setor)
SELECT * FROM vw_manutencao_tempo_medio_reparo; -- I8 (tempo médio de reparo)
SELECT * FROM vw_patrimonio_por_responsavel;    -- I9 (patrimônio por responsável)
SELECT * FROM vw_auditoria_patrimonio;          -- A10 (auditoria, alimentada pelas triggers)
SELECT * FROM vw_bens_criticos;                 -- A11 (view sobre view)

--  VIEWS DA VERSÃO 3 (setor, categoria, movimentação, SLA, alertas)
SELECT * FROM vw_setores_resumo;
SELECT * FROM vw_categorias_resumo;
SELECT * FROM vw_equipamentos_em_movimentacao;
SELECT * FROM vw_movimentacoes;
SELECT * FROM vw_chamados_sla;
SELECT * FROM vw_historico_chamados;
SELECT * FROM vw_manutencoes_em_andamento;
SELECT * FROM vw_ranking_tecnicos;
SELECT * FROM vw_conservacao_por_categoria;
SELECT * FROM vw_perfis_de_acesso;
SELECT * FROM vw_alertas_operacionais;
SELECT * FROM vw_inconsistencias;               -- deve vir vazia em um banco íntegro


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


--  Procedures da versão 3 que só leem dados
CALL sp_listar_bens_setor(1, NULL, NULL, 1, 'nome');
CALL sp_contar_bens_setor(1, 'status');
CALL sp_listar_bens_categoria(1, NULL, NULL);
CALL sp_relatorio_operacional('2026-01-01', '2026-12-31', 50.00, 1);   -- 7 resultados
CALL sp_historico_equipamento(1);


-- ------------------------------------------------------------
--  4) FLUXO DO CHAMADO (ALTERA dados) - descomente um bloco por vez
--     As procedures abrem e confirmam a própria transação (COMMIT).
-- ------------------------------------------------------------
--   -- abre o chamado (prioridade NULL = o banco classifica pela descrição)
--   CALL sp_abrir_chamado(4, 4, NULL, 'Cadeira com o encosto quebrado, risco de queda', '');
--   SELECT id_chamado, prioridade, status FROM chamado ORDER BY id_chamado DESC LIMIT 1;
--   SELECT * FROM vw_historico_chamados ORDER BY data_alteracao DESC LIMIT 3;
--
--   -- o admin leva o chamado adiante (troque 8 pelo id do chamado criado acima)
--   CALL sp_alterar_status_chamado(8, 'em_analise', 1, 'Triagem feita');
--   CALL sp_iniciar_manutencao(8, 'Carlos', 'Troca do encosto', 80.00, 1);
--   SELECT * FROM vw_manutencoes_em_andamento;
--   SELECT status FROM equipamento WHERE id_equipamento = 4;      -- em_manutencao (trigger)
--
--   -- registra um procedimento extra e conclui
--   CALL sp_registrar_procedimento(5, 'Parafusos novos', 15.00);
--   CALL sp_concluir_manutencao(5, 1, 'bom', 'Reparo concluído', 1);
--   SELECT status FROM equipamento WHERE id_equipamento = 4;      -- disponivel de novo
--
--   -- regras que devolvem erro (45404 / 45409 / 45422 / 45400)
--   CALL sp_alterar_status_chamado(9999, 'aberto', 1, '');
--   CALL sp_alterar_status_chamado(8, 'em_analise', 1, '');       -- concluído só reabre
--   CALL sp_remover_usuario(1);
--   INSERT INTO usuario (nome,email,senha,cpf,data_nascimento)
--          VALUES ('Fulano','fulano@x.com','x','111.111.111-11','1990-01-01');   -- CPF inválido


-- ------------------------------------------------------------
--  5) MOVIMENTAÇÃO DE PATRIMÔNIO, CONSERVAÇÃO E BAIXA (ALTERA dados)
-- ------------------------------------------------------------
--   -- transferência em duas etapas (o bem fica "em trânsito" no meio)
--   CALL sp_iniciar_movimentacao(8, 2, 1, 'Levar para a sala 3');
--   SELECT * FROM vw_equipamentos_em_movimentacao;
--   CALL sp_concluir_movimentacao(8, 1);
--   SELECT nome, localizacao, id_setor FROM equipamento WHERE id_equipamento = 8;
--
--   -- transferência direta (atalho) e auditoria
--   CALL sp_transferir_equipamento(4, 'Sala 7');
--   SELECT * FROM log_patrimonio ORDER BY id_log DESC LIMIT 5;
--
--   -- estado de conservação: piorar é livre; melhorar 2 níveis exige manutenção concluída
--   CALL sp_atualizar_estado_conservacao(4, 'regular', 1, 'Desgaste visível');
--
--   -- baixa e reativação
--   CALL sp_baixar_equipamento(5, 1);
--   CALL sp_abrir_chamado(2, 5, NULL, 'Teste em equipamento inativo', '');   -- erro 45422
--   CALL sp_reativar_equipamento(5, 1);
--
--   -- erro esperado: bem com chamado ativo não é excluído (45409)
--   DELETE FROM equipamento WHERE id_equipamento = 2;
--
--   -- volta tudo como estava
--   CALL sp_transferir_equipamento(4, 'Sala 2');


-- ------------------------------------------------------------
--  6) USUÁRIOS (ALTERA dados)
-- ------------------------------------------------------------
--   CALL sp_desativar_usuario(4, 1);      -- admin desativa; falha se tiver chamado ativo
--   CALL sp_reativar_usuario(4, 1);
--   -- o último admin ativo não pode ser rebaixado nem desativado (45422)
--   CALL sp_desativar_usuario(1, 1);
--   -- e-mail normalizado pelo trigger
--   UPDATE usuario SET email = '  TESTE@Escola.COM ' WHERE id_usuario = 4;
--   SELECT id_usuario, email FROM usuario WHERE id_usuario = 4;
--   UPDATE usuario SET email = 'ana@gmail.com' WHERE id_usuario = 4;
