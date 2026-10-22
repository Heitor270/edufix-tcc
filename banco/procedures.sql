--  Tópico 5 - Procedures de Consultas Complexas

USE inventario_escolar;

DELIMITER $$

-- Retorna um resumo completo de cada equipamento com seus
-- chamados, manutenções e custos totais.
-- Parâmetro: p_categoria (NULL = todos, ou filtrar por categoria)

DROP PROCEDURE IF EXISTS sp_resumo_equipamentos $$

CREATE PROCEDURE sp_resumo_equipamentos(IN p_categoria VARCHAR(50))
BEGIN
    SELECT
        e.id_equipamento                                AS id_equipamento,
        e.nome                                          AS nome_equipamento,
        e.categoria                                     AS categoria,
        e.localizacao                                   AS localizacao,
        e.estado_conservacao                            AS conservacao,
        fn_verificar_disponibilidade(e.id_equipamento)  AS disponibilidade,
        fn_total_chamados_equipamento(e.id_equipamento) AS total_chamados,
        fn_custo_total_manutencao(e.id_equipamento)     AS custo_total_manutencao,
        COUNT(m.id_manutencao)                          AS total_manutencoes_realizadas,
        MAX(m.data_fim)                                 AS data_ultima_manutencao

    FROM equipamento e
    LEFT JOIN chamado    c ON e.id_equipamento = c.id_equipamento
    LEFT JOIN manutencao m ON e.id_equipamento = m.id_equipamento

    WHERE (p_categoria IS NULL OR e.categoria = p_categoria)

    GROUP BY
        e.id_equipamento,
        e.nome,
        e.categoria,
        e.localizacao,
        e.estado_conservacao

    HAVING
        fn_total_chamados_equipamento(e.id_equipamento) > 0
        OR COUNT(m.id_manutencao) > 0

    ORDER BY
        custo_total_manutencao  DESC,
        total_chamados          DESC;
END $$


-- Retorna chamados com dados completos do usuário, equipamento
-- e total de manutenções vinculadas.
-- Parâmetro: p_status (NULL = todos, ou 'aberto', 'concluido', etc.)

DROP PROCEDURE IF EXISTS sp_chamados_detalhados $$

CREATE PROCEDURE sp_chamados_detalhados(IN p_status VARCHAR(20))
BEGIN
    SELECT
        c.id_chamado                                AS id_chamado,
        c.status                                    AS status,
        c.prioridade                                AS prioridade,
        c.data_abertura                             AS data_abertura,
        c.data_fechamento                           AS data_fechamento,
        fn_tempo_resolucao_chamado(c.id_chamado)    AS dias_resolucao,
        c.descricao_problema                        AS descricao,
        u.nome                                      AS nome_usuario,
        u.email                                     AS email_usuario,
        e.nome                                      AS nome_equipamento,
        e.localizacao                               AS localizacao_equipamento,
        e.categoria                                 AS categoria_equipamento,
        COUNT(m.id_manutencao)                      AS total_manutencoes

    FROM chamado c
    INNER JOIN usuario    u ON c.id_usuario     = u.id_usuario
    LEFT  JOIN equipamento e ON c.id_equipamento = e.id_equipamento
    LEFT  JOIN manutencao  m ON c.id_chamado     = m.id_chamado

    WHERE (p_status IS NULL OR c.status = p_status)

    GROUP BY
        c.id_chamado,
        c.status,
        c.prioridade,
        c.data_abertura,
        c.data_fechamento,
        c.descricao_problema,
        u.nome,
        u.email,
        e.nome,
        e.localizacao,
        e.categoria

    ORDER BY
        FIELD(c.prioridade, 'critica', 'alta', 'media', 'baixa'),
        c.data_abertura DESC;
END $$



-- Retorna indicadores de atividade de cada usuário ativo:
-- chamados abertos, interações de status e último chamado.

DROP PROCEDURE IF EXISTS sp_desempenho_usuarios $$

CREATE PROCEDURE sp_desempenho_usuarios()
BEGIN
    SELECT
        u.id_usuario                                    AS id_usuario,
        u.nome                                          AS nome_usuario,
        u.email                                         AS email,
        u.tipo_usuario                                  AS tipo,
        COUNT(DISTINCT c.id_chamado)                    AS total_chamados_criados,
        fn_total_chamados_abertos(u.id_usuario)         AS chamados_ainda_abertos,
        COUNT(DISTINCT h.id_historico)                  AS total_interacoes_status,
        MAX(c.data_abertura)                            AS ultimo_chamado_criado

    FROM usuario u
    LEFT JOIN chamado                c  ON u.id_usuario = c.id_usuario
    LEFT JOIN historico_status_chamado h ON u.id_usuario = h.id_usuario

    WHERE u.ativo = TRUE

    GROUP BY
        u.id_usuario,
        u.nome,
        u.email,
        u.tipo_usuario

    HAVING COUNT(DISTINCT c.id_chamado) > 0

    ORDER BY
        total_chamados_criados  DESC,
        total_interacoes_status DESC;
END $$


-- ============================================================
--  PROCEDURES DAS CONSULTAS COM PARÂMETRO (tela Consultas)
--  As consultas sem parâmetro estão em views.sql.
-- ============================================================

-- S2 - Equipamentos de uma categoria.
-- Parâmetro: p_categoria (NULL ou '' = todas as categorias)

DROP PROCEDURE IF EXISTS sp_equipamentos_por_categoria $$

CREATE PROCEDURE sp_equipamentos_por_categoria(IN p_categoria VARCHAR(50))
BEGIN
    SELECT nome, categoria, status, estado_conservacao, localizacao
    FROM equipamento
    WHERE p_categoria IS NULL
       OR p_categoria = ''
       OR categoria = p_categoria
    ORDER BY categoria, nome;
END $$


-- S4 - Busca parcial por nome ou número de patrimônio.
-- Os caracteres especiais do LIKE (\ % _) digitados pelo usuário são
-- escapados aqui dentro, para serem tratados como texto comum.

DROP PROCEDURE IF EXISTS sp_buscar_equipamento $$

CREATE PROCEDURE sp_buscar_equipamento(IN p_busca VARCHAR(100))
BEGIN
    DECLARE v_busca VARCHAR(300);

    SET v_busca = REPLACE(REPLACE(REPLACE(COALESCE(p_busca, ''),
                          '\\', '\\\\'), '%', '\\%'), '_', '\\_');

    SELECT numero_patrimonio, nome, categoria, localizacao, status
    FROM equipamento
    WHERE nome LIKE CONCAT('%', v_busca, '%')
       OR numero_patrimonio LIKE CONCAT('%', v_busca, '%')
    ORDER BY nome;
END $$


-- S5 - Equipamentos adquiridos entre duas datas (BETWEEN).

DROP PROCEDURE IF EXISTS sp_equipamentos_por_periodo $$

CREATE PROCEDURE sp_equipamentos_por_periodo(IN p_data_ini DATE, IN p_data_fim DATE)
BEGIN
    SELECT nome, categoria, numero_patrimonio, data_aquisicao
    FROM equipamento
    WHERE data_aquisicao BETWEEN p_data_ini AND p_data_fim
    ORDER BY data_aquisicao;
END $$


-- I1 - Chamados com solicitante e equipamento (INNER JOIN + LEFT JOIN).
-- Parâmetro: p_status (NULL ou '' = todos)

DROP PROCEDURE IF EXISTS sp_chamados_com_solicitante $$

CREATE PROCEDURE sp_chamados_com_solicitante(IN p_status VARCHAR(20))
BEGIN
    SELECT c.id_chamado, u.nome AS solicitante, e.nome AS equipamento,
           c.prioridade, c.status, c.data_abertura
    FROM chamado c
    INNER JOIN usuario u ON u.id_usuario = c.id_usuario
    LEFT JOIN equipamento e ON e.id_equipamento = c.id_equipamento
    WHERE p_status IS NULL
       OR p_status = ''
       OR c.status = p_status
    ORDER BY c.data_abertura DESC;
END $$


-- I4 - Equipamentos reincidentes: com pelo menos N chamados (GROUP BY + HAVING).

DROP PROCEDURE IF EXISTS sp_equipamentos_reincidentes $$

CREATE PROCEDURE sp_equipamentos_reincidentes(IN p_minimo INT)
BEGIN
    SELECT e.nome, e.numero_patrimonio, COUNT(c.id_chamado) AS total_chamados
    FROM equipamento e
    INNER JOIN chamado c ON c.id_equipamento = e.id_equipamento
    GROUP BY e.id_equipamento, e.nome, e.numero_patrimonio
    HAVING COUNT(c.id_chamado) >= COALESCE(p_minimo, 1)
    ORDER BY total_chamados DESC, e.nome;
END $$


-- A7 - Usuários que abriram chamados em pelo menos N categorias diferentes
-- (COUNT DISTINCT + HAVING + 3 tabelas).

DROP PROCEDURE IF EXISTS sp_usuarios_multiplas_categorias $$

CREATE PROCEDURE sp_usuarios_multiplas_categorias(IN p_minimo INT)
BEGIN
    SELECT u.nome,
           COUNT(DISTINCT e.categoria) AS categorias_distintas,
           COUNT(*)                    AS chamados
    FROM usuario u
    INNER JOIN chamado c     ON c.id_usuario     = u.id_usuario
    INNER JOIN equipamento e ON e.id_equipamento = c.id_equipamento
    GROUP BY u.id_usuario, u.nome
    HAVING COUNT(DISTINCT e.categoria) >= COALESCE(p_minimo, 1)
    ORDER BY categorias_distintas DESC, chamados DESC, u.nome;
END $$


-- A9 - Linha do tempo: une chamados e manutenções numa lista cronológica
-- (UNION ALL + CAST + LIMIT com parâmetro).

DROP PROCEDURE IF EXISTS sp_linha_do_tempo $$

CREATE PROCEDURE sp_linha_do_tempo(IN p_limite INT)
BEGIN
    DECLARE v_limite INT DEFAULT 10;

    IF p_limite IS NOT NULL AND p_limite > 0 THEN
        SET v_limite = p_limite;
    END IF;

    SELECT 'Chamado'               AS tipo,
           c.data_abertura         AS data_evento,
           c.descricao_problema    AS descricao
    FROM chamado c
    UNION ALL
    SELECT 'Manutenção',
           CAST(m.data_inicio AS DATETIME),
           m.descricao_servico
    FROM manutencao m
    ORDER BY data_evento DESC
    LIMIT v_limite;
END $$


-- ============================================================
--  PROCEDURES DE OPERAÇÃO (regras de negócio dentro do banco)
--  Erros de regra usam SIGNAL SQLSTATE '45xxx':
--    45404 = registro não encontrado | 45409 = conflito (vínculos)
-- ============================================================

-- Altera o status de um chamado e grava a alteração no histórico,
-- tudo numa única transação (ou grava os dois, ou nenhum).
-- A data_fechamento é preenchida pela trigger trg_chamado_data_fechamento.

DROP PROCEDURE IF EXISTS sp_alterar_status_chamado $$

CREATE PROCEDURE sp_alterar_status_chamado(
    IN p_id_chamado  INT,
    IN p_status_novo VARCHAR(20),
    IN p_id_usuario  INT,
    IN p_observacao  TEXT
)
BEGIN
    DECLARE v_status_anterior VARCHAR(20);
    DECLARE v_achou           TINYINT DEFAULT 1;

    DECLARE CONTINUE HANDLER FOR NOT FOUND SET v_achou = 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;

    SELECT status INTO v_status_anterior
    FROM chamado
    WHERE id_chamado = p_id_chamado
    FOR UPDATE;

    IF v_achou = 0 THEN
        SIGNAL SQLSTATE '45404'
            SET MESSAGE_TEXT = 'Chamado não encontrado.';
    END IF;

    UPDATE chamado
    SET status = p_status_novo
    WHERE id_chamado = p_id_chamado;

    INSERT INTO historico_status_chamado
        (id_chamado, id_usuario, status_anterior, status_novo, observacao)
    VALUES
        (p_id_chamado, p_id_usuario, v_status_anterior, p_status_novo, p_observacao);

    COMMIT;
END $$


-- Acerta o status do equipamento conforme as manutenções:
--   * existe manutenção sem data_fim  -> 'em_manutencao'
--   * não existe mais e estava 'em_manutencao' -> volta a 'disponivel'
-- Chamada pelas triggers da tabela manutencao.

DROP PROCEDURE IF EXISTS sp_sincronizar_equipamento $$

CREATE PROCEDURE sp_sincronizar_equipamento(IN p_id_equipamento INT)
BEGIN
    IF p_id_equipamento IS NOT NULL THEN
        IF fn_manutencoes_em_andamento(p_id_equipamento) > 0 THEN
            UPDATE equipamento
            SET status = 'em_manutencao'
            WHERE id_equipamento = p_id_equipamento
              AND status <> 'em_manutencao';
        ELSE
            UPDATE equipamento
            SET status = 'disponivel'
            WHERE id_equipamento = p_id_equipamento
              AND status = 'em_manutencao';
        END IF;
    END IF;
END $$


-- Torna um usuário administrador (ou atualiza nível/permissões se já for).
-- Parâmetros: p_nivel de 1 a 5 (regra CHECK da tabela admin).

DROP PROCEDURE IF EXISTS sp_promover_admin $$

CREATE PROCEDURE sp_promover_admin(
    IN p_id_usuario INT,
    IN p_nivel      INT,
    IN p_permissoes TEXT
)
BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    IF NOT EXISTS (SELECT 1 FROM usuario WHERE id_usuario = p_id_usuario) THEN
        SIGNAL SQLSTATE '45404'
            SET MESSAGE_TEXT = 'Usuário não encontrado.';
    END IF;

    START TRANSACTION;

    UPDATE usuario
    SET tipo_usuario = 'admin'
    WHERE id_usuario = p_id_usuario;

    INSERT INTO admin (id_admin, nivel_acesso, permissoes)
    VALUES (p_id_usuario, p_nivel, p_permissoes)
    ON DUPLICATE KEY UPDATE
        nivel_acesso = VALUES(nivel_acesso),
        permissoes   = VALUES(permissoes);

    COMMIT;
END $$


-- Remove um usuário somente se ele não tiver chamados nem histórico
-- (usa fn_total_vinculos_usuario). Caso tenha, o correto é desativá-lo.

DROP PROCEDURE IF EXISTS sp_remover_usuario $$

CREATE PROCEDURE sp_remover_usuario(IN p_id_usuario INT)
BEGIN
    IF NOT EXISTS (SELECT 1 FROM usuario WHERE id_usuario = p_id_usuario) THEN
        SIGNAL SQLSTATE '45404'
            SET MESSAGE_TEXT = 'Usuário não encontrado.';
    END IF;

    IF fn_total_vinculos_usuario(p_id_usuario) > 0 THEN
        SIGNAL SQLSTATE '45409'
            SET MESSAGE_TEXT = 'Esse usuário tem chamados/histórico registrados e não pode ser removido. Use Editar → Situação: Inativo para desativá-lo.';
    END IF;

    DELETE FROM usuario WHERE id_usuario = p_id_usuario;
END $$

DELIMITER ;
