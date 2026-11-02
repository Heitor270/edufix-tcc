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

-- ============================================================
--  PROCEDURES DE APOIO (usadas pelas triggers e por outras procedures)
-- ============================================================

-- Garante que o setor / a categoria existe na tabela (cria se faltar).
-- Chamadas pelo trigger do equipamento, que liga o bem a setor e categoria.

DROP PROCEDURE IF EXISTS sp_garantir_setor $$

CREATE PROCEDURE sp_garantir_setor(IN p_nome VARCHAR(100))
BEGIN
    INSERT INTO setor (nome)
    SELECT p_nome FROM DUAL
    WHERE NOT EXISTS (SELECT 1 FROM setor WHERE nome = p_nome);
END $$


DROP PROCEDURE IF EXISTS sp_garantir_categoria $$

CREATE PROCEDURE sp_garantir_categoria(IN p_nome VARCHAR(50))
BEGIN
    INSERT INTO categoria (nome)
    SELECT p_nome FROM DUAL
    WHERE NOT EXISTS (SELECT 1 FROM categoria WHERE nome = p_nome);
END $$


-- Acerta o status do equipamento conforme as manutenções e os chamados:
--   * existe manutenção sem data_fim  -> 'em_manutencao'
--   * não existe mais e estava 'em_manutencao' -> volta a 'disponivel'
--   * bem 'inutilizavel' sem chamado ativo nem manutenção aberta -> 'inativo' (baixa)
-- Chamada pelas triggers das tabelas manutencao e chamado.

DROP PROCEDURE IF EXISTS sp_sincronizar_equipamento $$

CREATE PROCEDURE sp_sincronizar_equipamento(IN p_id_equipamento INT)
BEGIN
    IF p_id_equipamento IS NOT NULL THEN
        IF fn_manutencoes_em_andamento(p_id_equipamento) > 0 THEN
            UPDATE equipamento
            SET status = 'em_manutencao'
            WHERE id_equipamento = p_id_equipamento
              AND status NOT IN ('em_manutencao', 'inativo');
        ELSE
            UPDATE equipamento
            SET status = 'disponivel'
            WHERE id_equipamento = p_id_equipamento
              AND status = 'em_manutencao';
        END IF;

        UPDATE equipamento
        SET status = 'inativo'
        WHERE id_equipamento = p_id_equipamento
          AND estado_conservacao = 'inutilizavel'
          AND status IN ('disponivel', 'em_uso')
          AND fn_chamados_ativos_equipamento(p_id_equipamento) = 0
          AND fn_manutencoes_em_andamento(p_id_equipamento) = 0;
    END IF;
END $$


-- ============================================================
--  CHAMADO: abertura, status, encerramento (classe Chamado)
-- ============================================================

-- Regra única de mudança de status (usada por sp_alterar_status_chamado,
-- sp_encerrar_chamado, sp_iniciar_manutencao e sp_concluir_manutencao).
-- NÃO abre transação: quem chama é que controla o COMMIT.
-- Valida: chamado/usuário existem e o usuário está ativo, transição permitida
-- (fn_transicao_status_valida), permissão (admin faz tudo; o autor só cancela o
-- próprio chamado ainda 'aberto'), equipamento ativo para executar/reabrir e
-- nenhuma manutenção em andamento para concluir/cancelar. Grava o histórico.

DROP PROCEDURE IF EXISTS sp_aplicar_status_chamado $$

CREATE PROCEDURE sp_aplicar_status_chamado(
    IN p_id_chamado  INT,
    IN p_status_novo VARCHAR(20),
    IN p_id_usuario  INT,
    IN p_observacao  TEXT
)
BEGIN
    DECLARE v_anterior VARCHAR(20);
    DECLARE v_equip    INT;
    DECLARE v_dono     INT;
    DECLARE v_achou    TINYINT DEFAULT 1;
    DECLARE v_obs      TEXT;
    DECLARE v_msg      VARCHAR(128);

    DECLARE CONTINUE HANDLER FOR NOT FOUND SET v_achou = 0;

    SELECT status, id_equipamento, id_usuario
    INTO v_anterior, v_equip, v_dono
    FROM chamado
    WHERE id_chamado = p_id_chamado
    FOR UPDATE;

    IF v_achou = 0 THEN
        SIGNAL SQLSTATE '45404' SET MESSAGE_TEXT = 'Chamado não encontrado.';
    END IF;
    IF p_status_novo NOT IN ('aberto', 'em_analise', 'em_execucao', 'concluido', 'cancelado') THEN
        SIGNAL SQLSTATE '45400' SET MESSAGE_TEXT = 'Status inválido.';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM usuario WHERE id_usuario = p_id_usuario) THEN
        SIGNAL SQLSTATE '45404' SET MESSAGE_TEXT = 'Usuário não encontrado.';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM usuario WHERE id_usuario = p_id_usuario AND ativo = TRUE) THEN
        SIGNAL SQLSTATE '45403' SET MESSAGE_TEXT = 'Usuário inativo.';
    END IF;
    IF v_anterior = p_status_novo THEN
        SIGNAL SQLSTATE '45422' SET MESSAGE_TEXT = 'O chamado já está com este status.';
    END IF;
    IF fn_transicao_status_valida(v_anterior, p_status_novo) = 0 THEN
        SET v_msg = CONCAT('Transição inválida: ', v_anterior, ' -> ', p_status_novo, '.');
        SIGNAL SQLSTATE '45422' SET MESSAGE_TEXT = v_msg;
    END IF;

    IF fn_admin_tem_permissao(p_id_usuario, 'gerenciar_chamados') = 0 THEN
        IF NOT (p_id_usuario = v_dono AND p_status_novo = 'cancelado' AND v_anterior = 'aberto') THEN
            SIGNAL SQLSTATE '45403'
                SET MESSAGE_TEXT = 'Você só pode cancelar o seu próprio chamado enquanto ele estiver aberto.';
        END IF;
    END IF;

    IF p_status_novo IN ('aberto', 'em_execucao') AND v_equip IS NOT NULL
       AND fn_equipamento_inativo(v_equip) = 1 THEN
        SIGNAL SQLSTATE '45422'
            SET MESSAGE_TEXT = 'Equipamento inativo: não é possível reabrir ou executar o chamado.';
    END IF;
    IF p_status_novo IN ('concluido', 'cancelado')
       AND fn_manutencoes_em_andamento_chamado(p_id_chamado) > 0 THEN
        SIGNAL SQLSTATE '45409'
            SET MESSAGE_TEXT = 'Há manutenção em andamento: conclua-a antes de encerrar o chamado.';
    END IF;

    SET v_obs = NULLIF(TRIM(p_observacao), '');
    IF v_obs IS NULL AND p_status_novo = 'cancelado' THEN
        SET v_obs = 'Cancelado (motivo não informado)';
    ELSEIF v_obs IS NULL AND v_anterior IN ('concluido', 'cancelado') THEN
        SET v_obs = 'Chamado reaberto';
    END IF;

    SET @edufix_usuario = (SELECT CONCAT(nome, ' (id ', id_usuario, ')')
                           FROM usuario WHERE id_usuario = p_id_usuario);

    UPDATE chamado
    SET status = p_status_novo
    WHERE id_chamado = p_id_chamado;

    INSERT INTO historico_status_chamado
        (id_chamado, id_usuario, status_anterior, status_novo, observacao)
    VALUES
        (p_id_chamado, p_id_usuario, v_anterior, p_status_novo, v_obs);
END $$


-- Altera o status de um chamado e grava a alteração no histórico, tudo numa
-- única transação. A data_fechamento é preenchida pela trigger trg_chamado_data_fechamento.
-- (Método atualizarStatus da classe Chamado.)

DROP PROCEDURE IF EXISTS sp_alterar_status_chamado $$

CREATE PROCEDURE sp_alterar_status_chamado(
    IN p_id_chamado  INT,
    IN p_status_novo VARCHAR(20),
    IN p_id_usuario  INT,
    IN p_observacao  TEXT
)
BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SET @edufix_usuario = NULL;
        RESIGNAL;
    END;

    START TRANSACTION;
    CALL sp_aplicar_status_chamado(p_id_chamado, p_status_novo, p_id_usuario, p_observacao);
    SET @edufix_usuario = NULL;
    COMMIT;
END $$


-- Abre um chamado (método registrarAbertura da classe Chamado). Se a prioridade vier
-- vazia, o banco classifica sozinho (fn_classificar_prioridade). As validações
-- (usuário ativo, equipamento ativo, descrição, duplicidade) estão na trigger
-- trg_chamado_valida_equipamento e o 1º histórico é gravado por trg_chamado_after_insert.
-- Devolve o id, a prioridade usada e o status.

DROP PROCEDURE IF EXISTS sp_abrir_chamado $$

CREATE PROCEDURE sp_abrir_chamado(
    IN p_id_usuario     INT,
    IN p_id_equipamento INT,
    IN p_prioridade     VARCHAR(10),
    IN p_descricao      TEXT,
    IN p_observacoes    TEXT
)
BEGIN
    DECLARE v_prioridade VARCHAR(10);

    IF NOT EXISTS (SELECT 1 FROM usuario WHERE id_usuario = p_id_usuario) THEN
        SIGNAL SQLSTATE '45404' SET MESSAGE_TEXT = 'Usuário não encontrado.';
    END IF;
    IF p_id_equipamento IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM equipamento WHERE id_equipamento = p_id_equipamento) THEN
        SIGNAL SQLSTATE '45404' SET MESSAGE_TEXT = 'Equipamento não encontrado.';
    END IF;

    SET v_prioridade = NULLIF(TRIM(p_prioridade), '');
    IF v_prioridade IS NULL THEN
        SET v_prioridade = fn_classificar_prioridade(p_descricao, p_id_equipamento);
    ELSEIF v_prioridade NOT IN ('baixa', 'media', 'alta', 'critica') THEN
        SIGNAL SQLSTATE '45400' SET MESSAGE_TEXT = 'Prioridade inválida.';
    END IF;

    INSERT INTO chamado (id_usuario, id_equipamento, prioridade, descricao_problema, observacoes)
    VALUES (p_id_usuario, p_id_equipamento, v_prioridade, p_descricao, COALESCE(p_observacoes, ''));

    SELECT LAST_INSERT_ID() AS id_chamado, v_prioridade AS prioridade, 'aberto' AS status;
END $$


-- Reclassifica a prioridade de um chamado em aberto/em análise (método classificarPrioridade).
-- Só SOBE a prioridade, nunca reduz uma escolhida pelo usuário. Anota a mudança em observacoes.

DROP PROCEDURE IF EXISTS sp_reclassificar_chamado $$

CREATE PROCEDURE sp_reclassificar_chamado(IN p_id_chamado INT)
BEGIN
    DECLARE v_status VARCHAR(20);
    DECLARE v_atual  VARCHAR(10);
    DECLARE v_desc   TEXT;
    DECLARE v_equip  INT;
    DECLARE v_nova   VARCHAR(10);
    DECLARE v_achou  TINYINT DEFAULT 1;
    DECLARE CONTINUE HANDLER FOR NOT FOUND SET v_achou = 0;

    SELECT status, prioridade, descricao_problema, id_equipamento
    INTO v_status, v_atual, v_desc, v_equip
    FROM chamado
    WHERE id_chamado = p_id_chamado;

    IF v_achou = 0 THEN
        SIGNAL SQLSTATE '45404' SET MESSAGE_TEXT = 'Chamado não encontrado.';
    END IF;
    IF v_status NOT IN ('aberto', 'em_analise') THEN
        SIGNAL SQLSTATE '45422'
            SET MESSAGE_TEXT = 'Só se reclassifica chamado aberto ou em análise.';
    END IF;

    SET v_nova = fn_classificar_prioridade(v_desc, v_equip);

    IF FIELD(v_nova, 'baixa', 'media', 'alta', 'critica') > FIELD(v_atual, 'baixa', 'media', 'alta', 'critica') THEN
        UPDATE chamado
        SET prioridade  = v_nova,
            observacoes = CONCAT_WS(CHAR(10), NULLIF(observacoes, ''),
                                    CONCAT('[', DATE_FORMAT(NOW(), '%d/%m/%Y %H:%i'), '] Prioridade ',
                                           v_atual, ' -> ', v_nova, ' (classificação automática)'))
        WHERE id_chamado = p_id_chamado;
    END IF;

    SELECT p_id_chamado AS id_chamado, v_atual AS prioridade_anterior,
           prioridade AS prioridade_atual, (prioridade <> v_atual) AS alterada
    FROM chamado
    WHERE id_chamado = p_id_chamado;
END $$


-- Encerra um chamado (método encerrarChamado). p_resolvido = 1 conclui (avançando sozinho
-- até 'em_execucao' se preciso, deixando histórico) e 0 cancela (motivo na observação).
-- Não encerra com manutenção em andamento. Tudo numa transação.

DROP PROCEDURE IF EXISTS sp_encerrar_chamado $$

CREATE PROCEDURE sp_encerrar_chamado(
    IN p_id_chamado INT,
    IN p_id_usuario INT,
    IN p_observacao TEXT,
    IN p_resolvido  TINYINT
)
BEGIN
    DECLARE v_status VARCHAR(20);
    DECLARE v_achou  TINYINT DEFAULT 1;
    DECLARE CONTINUE HANDLER FOR NOT FOUND SET v_achou = 0;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SET @edufix_usuario = NULL;
        RESIGNAL;
    END;

    START TRANSACTION;

    SELECT status INTO v_status FROM chamado WHERE id_chamado = p_id_chamado FOR UPDATE;
    IF v_achou = 0 THEN
        SIGNAL SQLSTATE '45404' SET MESSAGE_TEXT = 'Chamado não encontrado.';
    END IF;
    IF v_status NOT IN ('aberto', 'em_analise', 'em_execucao') THEN
        SIGNAL SQLSTATE '45422' SET MESSAGE_TEXT = 'Chamado já encerrado.';
    END IF;

    IF COALESCE(p_resolvido, 1) = 0 THEN
        CALL sp_aplicar_status_chamado(p_id_chamado, 'cancelado', p_id_usuario, p_observacao);
    ELSE
        IF v_status = 'aberto' THEN
            CALL sp_aplicar_status_chamado(p_id_chamado, 'em_analise', p_id_usuario, 'Avanço automático ao encerrar');
            SET v_status = 'em_analise';
        END IF;
        IF v_status = 'em_analise' THEN
            CALL sp_aplicar_status_chamado(p_id_chamado, 'em_execucao', p_id_usuario, 'Avanço automático ao encerrar');
        END IF;
        CALL sp_aplicar_status_chamado(p_id_chamado, 'concluido', p_id_usuario, p_observacao);
    END IF;

    SET @edufix_usuario = NULL;
    COMMIT;

    SELECT id_chamado, status, data_fechamento FROM chamado WHERE id_chamado = p_id_chamado;
END $$


-- ============================================================
--  MANUTENÇÃO (classe Manutencao)
-- ============================================================

-- iniciarAtendimento: cria a manutenção ligada ao CHAMADO (o equipamento é o do chamado),
-- leva o chamado a 'em_execucao' (passando por 'em_analise' com histórico) e, pela
-- trigger, o equipamento fica 'em_manutencao'. Só administrador com permissão de chamados.

DROP PROCEDURE IF EXISTS sp_iniciar_manutencao $$

CREATE PROCEDURE sp_iniciar_manutencao(
    IN p_id_chamado INT,
    IN p_tecnico    VARCHAR(100),
    IN p_descricao  TEXT,
    IN p_custo      DECIMAL(10, 2),
    IN p_id_usuario INT
)
BEGIN
    DECLARE v_status VARCHAR(20);
    DECLARE v_equip  INT;
    DECLARE v_id     INT;
    DECLARE v_achou  TINYINT DEFAULT 1;
    DECLARE CONTINUE HANDLER FOR NOT FOUND SET v_achou = 0;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SET @edufix_usuario = NULL;
        RESIGNAL;
    END;

    IF fn_admin_tem_permissao(p_id_usuario, 'gerenciar_chamados') = 0 THEN
        SIGNAL SQLSTATE '45403'
            SET MESSAGE_TEXT = 'Apenas administradores com permissão de chamados executam manutenções.';
    END IF;

    START TRANSACTION;

    SELECT status, id_equipamento INTO v_status, v_equip
    FROM chamado WHERE id_chamado = p_id_chamado FOR UPDATE;

    IF v_achou = 0 THEN
        SIGNAL SQLSTATE '45404' SET MESSAGE_TEXT = 'Chamado não encontrado.';
    END IF;
    IF v_equip IS NULL THEN
        SIGNAL SQLSTATE '45422' SET MESSAGE_TEXT = 'O chamado não tem equipamento vinculado.';
    END IF;

    SET @edufix_usuario = (SELECT CONCAT(nome, ' (id ', id_usuario, ')')
                           FROM usuario WHERE id_usuario = p_id_usuario);

    INSERT INTO manutencao
        (id_chamado, id_equipamento, data_inicio, descricao_servico, tecnico_responsavel, custo)
    VALUES
        (p_id_chamado, v_equip, CURDATE(), p_descricao, p_tecnico, COALESCE(p_custo, 0));
    SET v_id = LAST_INSERT_ID();

    IF v_status = 'aberto' THEN
        CALL sp_aplicar_status_chamado(p_id_chamado, 'em_analise', p_id_usuario, 'Atendimento iniciado');
        SET v_status = 'em_analise';
    END IF;
    IF v_status = 'em_analise' THEN
        CALL sp_aplicar_status_chamado(p_id_chamado, 'em_execucao', p_id_usuario,
                                       CONCAT('Manutenção #', v_id, ' iniciada'));
    END IF;

    SET @edufix_usuario = NULL;
    COMMIT;

    SELECT v_id AS id_manutencao, c.status AS status_chamado, e.status AS status_equipamento
    FROM chamado c
    INNER JOIN equipamento e ON e.id_equipamento = c.id_equipamento
    WHERE c.id_chamado = p_id_chamado;
END $$


-- registrarProcedimento: anota um passo do reparo (com data/hora) na descrição do
-- serviço e soma o custo de peças/serviços. Só em manutenção em andamento.

DROP PROCEDURE IF EXISTS sp_registrar_procedimento $$

CREATE PROCEDURE sp_registrar_procedimento(
    IN p_id_manutencao  INT,
    IN p_procedimento   VARCHAR(255),
    IN p_custo_adicional DECIMAL(10, 2)
)
BEGIN
    DECLARE v_fim    DATE;
    DECLARE v_achou  TINYINT DEFAULT 1;
    DECLARE v_linha  VARCHAR(400);
    DECLARE CONTINUE HANDLER FOR NOT FOUND SET v_achou = 0;

    SELECT data_fim INTO v_fim FROM manutencao WHERE id_manutencao = p_id_manutencao;

    IF v_achou = 0 THEN
        SIGNAL SQLSTATE '45404' SET MESSAGE_TEXT = 'Manutenção não encontrada.';
    END IF;
    IF v_fim IS NOT NULL THEN
        SIGNAL SQLSTATE '45422'
            SET MESSAGE_TEXT = 'Só é possível registrar procedimentos com a manutenção em andamento.';
    END IF;
    IF CHAR_LENGTH(COALESCE(TRIM(p_procedimento), '')) < 3 THEN
        SIGNAL SQLSTATE '45400' SET MESSAGE_TEXT = 'Descreva o procedimento.';
    END IF;
    IF COALESCE(p_custo_adicional, 0) < 0 THEN
        SIGNAL SQLSTATE '45400' SET MESSAGE_TEXT = 'Custo adicional não pode ser negativo.';
    END IF;

    SET v_linha = CONCAT('[', DATE_FORMAT(NOW(), '%d/%m/%Y %H:%i'), '] ', TRIM(p_procedimento),
                         IF(COALESCE(p_custo_adicional, 0) > 0,
                            CONCAT(' (R$ ', CAST(ROUND(p_custo_adicional, 2) AS CHAR), ')'), ''));

    UPDATE manutencao
    SET descricao_servico = CONCAT_WS(CHAR(10), NULLIF(descricao_servico, ''), v_linha),
        custo             = custo + COALESCE(p_custo_adicional, 0)
    WHERE id_manutencao = p_id_manutencao;

    SELECT v_linha AS procedimento_registrado, custo AS custo_acumulado
    FROM manutencao WHERE id_manutencao = p_id_manutencao;
END $$


-- concluirAtendimento: grava data_fim (a trigger devolve o equipamento a 'disponivel'),
-- reavalia a conservação se informada (regras do trigger do equipamento) e, com
-- p_encerrar_chamado = 1, já conclui o chamado. Devolve um resumo.

DROP PROCEDURE IF EXISTS sp_concluir_manutencao $$

CREATE PROCEDURE sp_concluir_manutencao(
    IN p_id_manutencao     INT,
    IN p_id_usuario        INT,
    IN p_estado_final      VARCHAR(20),
    IN p_observacao        TEXT,
    IN p_encerrar_chamado  TINYINT
)
BEGIN
    DECLARE v_chamado INT;
    DECLARE v_equip   INT;
    DECLARE v_fim     DATE;
    DECLARE v_desc    TEXT;
    DECLARE v_status  VARCHAR(20);
    DECLARE v_achou   TINYINT DEFAULT 1;
    DECLARE CONTINUE HANDLER FOR NOT FOUND SET v_achou = 0;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SET @edufix_usuario = NULL;
        RESIGNAL;
    END;

    IF fn_admin_tem_permissao(p_id_usuario, 'gerenciar_chamados') = 0 THEN
        SIGNAL SQLSTATE '45403'
            SET MESSAGE_TEXT = 'Apenas administradores com permissão de chamados executam manutenções.';
    END IF;
    IF NULLIF(p_estado_final, '') IS NOT NULL
       AND p_estado_final NOT IN ('otimo', 'bom', 'regular', 'ruim', 'inutilizavel') THEN
        SIGNAL SQLSTATE '45400' SET MESSAGE_TEXT = 'Estado de conservação inválido.';
    END IF;

    START TRANSACTION;

    SELECT id_chamado, id_equipamento, data_fim, descricao_servico
    INTO v_chamado, v_equip, v_fim, v_desc
    FROM manutencao WHERE id_manutencao = p_id_manutencao FOR UPDATE;

    IF v_achou = 0 THEN
        SIGNAL SQLSTATE '45404' SET MESSAGE_TEXT = 'Manutenção não encontrada.';
    END IF;
    IF v_fim IS NOT NULL THEN
        SIGNAL SQLSTATE '45422' SET MESSAGE_TEXT = 'Esta manutenção já foi concluída.';
    END IF;
    IF COALESCE(TRIM(v_desc), '') = '' THEN
        SIGNAL SQLSTATE '45400'
            SET MESSAGE_TEXT = 'Registre ao menos um procedimento antes de concluir.';
    END IF;

    SET @edufix_usuario = (SELECT CONCAT(nome, ' (id ', id_usuario, ')')
                           FROM usuario WHERE id_usuario = p_id_usuario);

    UPDATE manutencao SET data_fim = CURDATE() WHERE id_manutencao = p_id_manutencao;

    IF NULLIF(p_estado_final, '') IS NOT NULL THEN
        UPDATE equipamento SET estado_conservacao = p_estado_final WHERE id_equipamento = v_equip;
    END IF;

    IF COALESCE(p_encerrar_chamado, 0) = 1 THEN
        SELECT status INTO v_status FROM chamado WHERE id_chamado = v_chamado;
        IF v_status = 'aberto' THEN
            CALL sp_aplicar_status_chamado(v_chamado, 'em_analise', p_id_usuario, 'Avanço automático ao encerrar');
            SET v_status = 'em_analise';
        END IF;
        IF v_status = 'em_analise' THEN
            CALL sp_aplicar_status_chamado(v_chamado, 'em_execucao', p_id_usuario, 'Avanço automático ao encerrar');
        END IF;
        CALL sp_aplicar_status_chamado(v_chamado, 'concluido', p_id_usuario,
                                       COALESCE(NULLIF(TRIM(p_observacao), ''), 'Serviço concluído'));
    END IF;

    SET @edufix_usuario = NULL;
    COMMIT;

    SELECT m.id_manutencao,
           fn_custo_manutencao_total(m.id_manutencao, 0)       AS custo_total,
           DATEDIFF(m.data_fim, m.data_inicio) + 1             AS dias_trabalhados,
           e.status                                            AS status_equipamento,
           e.estado_conservacao                                AS conservacao_equipamento,
           c.status                                            AS status_chamado
    FROM manutencao m
    INNER JOIN equipamento e ON e.id_equipamento = m.id_equipamento
    INNER JOIN chamado c     ON c.id_chamado     = m.id_chamado
    WHERE m.id_manutencao = p_id_manutencao;
END $$


-- ============================================================
--  EQUIPAMENTO: localização, movimentação, conservação, baixa (classe Equipamento)
-- ============================================================

-- atualizarLocalizacao: CORRIGE a sala/descrição onde o bem está. A trigger de
-- auditoria registra a TRANSFERENCIA no log. Não vale para bem inativo nem em movimentação
-- (para mudar de setor, use as procedures de movimentação).

DROP PROCEDURE IF EXISTS sp_transferir_equipamento $$

CREATE PROCEDURE sp_transferir_equipamento(
    IN p_id_equipamento   INT,
    IN p_nova_localizacao VARCHAR(100)
)
BEGIN
    IF NOT EXISTS (SELECT 1 FROM equipamento WHERE id_equipamento = p_id_equipamento) THEN
        SIGNAL SQLSTATE '45404'
            SET MESSAGE_TEXT = 'Equipamento não encontrado.';
    END IF;

    IF fn_equipamento_inativo(p_id_equipamento) = 1 THEN
        SIGNAL SQLSTATE '45422'
            SET MESSAGE_TEXT = 'Equipamento inativo não pode ser transferido.';
    END IF;

    IF fn_equipamento_em_movimentacao(p_id_equipamento) = 1 THEN
        SIGNAL SQLSTATE '45409'
            SET MESSAGE_TEXT = 'Equipamento em movimentação: conclua ou cancele a movimentação antes.';
    END IF;

    IF p_nova_localizacao IS NULL OR CHAR_LENGTH(TRIM(p_nova_localizacao)) < 2 THEN
        SIGNAL SQLSTATE '45400'
            SET MESSAGE_TEXT = 'Informe a nova localização.';
    END IF;

    UPDATE equipamento
    SET localizacao = TRIM(p_nova_localizacao)
    WHERE id_equipamento = p_id_equipamento;
END $$


-- registrarMovimentacao (acao "iniciar"): o bem passa a estar EM TRÂNSITO para outro setor.
-- Só um administrador com permissão de patrimônio. O bem continua no setor de origem
-- até a movimentação ser concluída.

DROP PROCEDURE IF EXISTS sp_iniciar_movimentacao $$

CREATE PROCEDURE sp_iniciar_movimentacao(
    IN p_id_equipamento   INT,
    IN p_id_setor_destino INT,
    IN p_id_usuario       INT,
    IN p_observacao       VARCHAR(255)
)
BEGIN
    IF NOT EXISTS (SELECT 1 FROM equipamento WHERE id_equipamento = p_id_equipamento) THEN
        SIGNAL SQLSTATE '45404' SET MESSAGE_TEXT = 'Equipamento não encontrado.';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM setor WHERE id_setor = p_id_setor_destino) THEN
        SIGNAL SQLSTATE '45404' SET MESSAGE_TEXT = 'Setor de destino não encontrado.';
    END IF;
    IF fn_equipamento_em_movimentacao(p_id_equipamento) = 1 THEN
        SIGNAL SQLSTATE '45409' SET MESSAGE_TEXT = 'Este bem já está em movimentação.';
    END IF;

    INSERT INTO movimentacao_equipamento (id_equipamento, id_setor_destino, id_usuario, observacao)
    VALUES (p_id_equipamento, p_id_setor_destino, p_id_usuario, p_observacao);

    SELECT m.id_movimentacao, so.nome AS origem, sd.nome AS destino, m.situacao
    FROM movimentacao_equipamento m
    LEFT JOIN setor so ON so.id_setor = m.id_setor_origem
    INNER JOIN setor sd ON sd.id_setor = m.id_setor_destino
    WHERE m.id_movimentacao = LAST_INSERT_ID();
END $$


-- registrarMovimentacao (acao "concluir"): efetiva a troca. A localização do bem vira o
-- nome do setor de destino (a trigger acerta id_setor e grava TRANSFERENCIA no log).

DROP PROCEDURE IF EXISTS sp_concluir_movimentacao $$

CREATE PROCEDURE sp_concluir_movimentacao(
    IN p_id_equipamento INT,
    IN p_id_usuario     INT
)
BEGIN
    DECLARE v_mov     INT;
    DECLARE v_destino INT;
    DECLARE v_nome_destino VARCHAR(100);
    DECLARE v_achou   TINYINT DEFAULT 1;
    DECLARE CONTINUE HANDLER FOR NOT FOUND SET v_achou = 0;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SET @edufix_usuario = NULL;
        SET @edufix_movimentando = 0;
        RESIGNAL;
    END;

    IF fn_admin_tem_permissao(p_id_usuario, 'gerenciar_patrimonio') = 0 THEN
        SIGNAL SQLSTATE '45403'
            SET MESSAGE_TEXT = 'Apenas administradores com permissão de patrimônio movimentam bens.';
    END IF;

    START TRANSACTION;

    SELECT id_movimentacao, id_setor_destino INTO v_mov, v_destino
    FROM movimentacao_equipamento
    WHERE id_equipamento = p_id_equipamento AND situacao = 'em_transito'
    FOR UPDATE;

    IF v_achou = 0 THEN
        SIGNAL SQLSTATE '45404' SET MESSAGE_TEXT = 'Não há movimentação em andamento para este bem.';
    END IF;
    IF fn_equipamento_inativo(p_id_equipamento) = 1
       OR fn_manutencoes_em_andamento(p_id_equipamento) > 0 THEN
        SIGNAL SQLSTATE '45422'
            SET MESSAGE_TEXT = 'O bem ficou inativo/em manutenção durante o trânsito: cancele a movimentação.';
    END IF;

    SET @edufix_usuario = (SELECT CONCAT(nome, ' (id ', id_usuario, ')')
                           FROM usuario WHERE id_usuario = p_id_usuario);
    SET @edufix_movimentando = 1;

    -- o nome é lido antes do UPDATE: a trigger do equipamento pode gravar em setor
    -- e o MySQL não deixa o mesmo comando ler e alterar a tabela por dentro da trigger.
    SELECT nome INTO v_nome_destino FROM setor WHERE id_setor = v_destino;

    UPDATE equipamento
    SET localizacao = v_nome_destino
    WHERE id_equipamento = p_id_equipamento;

    SET @edufix_movimentando = 0;

    UPDATE movimentacao_equipamento
    SET situacao = 'concluida'
    WHERE id_movimentacao = v_mov;

    SET @edufix_usuario = NULL;
    COMMIT;

    SELECT e.id_equipamento, e.nome, e.localizacao, s.nome AS setor,
           fn_equipamento_em_movimentacao(e.id_equipamento) AS em_movimentacao
    FROM equipamento e
    LEFT JOIN setor s ON s.id_setor = e.id_setor
    WHERE e.id_equipamento = p_id_equipamento;
END $$


-- registrarMovimentacao (acao "cancelar"): desfaz a movimentação sem alterar o bem.

DROP PROCEDURE IF EXISTS sp_cancelar_movimentacao $$

CREATE PROCEDURE sp_cancelar_movimentacao(
    IN p_id_equipamento INT,
    IN p_id_usuario     INT
)
BEGIN
    IF fn_admin_tem_permissao(p_id_usuario, 'gerenciar_patrimonio') = 0 THEN
        SIGNAL SQLSTATE '45403'
            SET MESSAGE_TEXT = 'Apenas administradores com permissão de patrimônio movimentam bens.';
    END IF;
    IF fn_equipamento_em_movimentacao(p_id_equipamento) = 0 THEN
        SIGNAL SQLSTATE '45404' SET MESSAGE_TEXT = 'Não há movimentação em andamento para este bem.';
    END IF;

    UPDATE movimentacao_equipamento
    SET situacao = 'cancelada'
    WHERE id_equipamento = p_id_equipamento AND situacao = 'em_transito';

    SELECT p_id_equipamento AS id_equipamento, 0 AS em_movimentacao;
END $$


-- atualizarEstadoConservacao: só admin com permissão de patrimônio; motivo obrigatório
-- ao classificar como ruim/inutilizável. As demais regras (melhora de 2+ níveis, baixa
-- automática do bem inutilizável) estão no trigger trg_equipamento_before_update.

DROP PROCEDURE IF EXISTS sp_atualizar_estado_conservacao $$

CREATE PROCEDURE sp_atualizar_estado_conservacao(
    IN p_id_equipamento INT,
    IN p_estado         VARCHAR(20),
    IN p_id_usuario     INT,
    IN p_motivo         VARCHAR(255)
)
BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        SET @edufix_usuario = NULL;
        RESIGNAL;
    END;

    IF fn_admin_tem_permissao(p_id_usuario, 'gerenciar_patrimonio') = 0 THEN
        SIGNAL SQLSTATE '45403'
            SET MESSAGE_TEXT = 'Apenas administradores com permissão de patrimônio alteram bens.';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM equipamento WHERE id_equipamento = p_id_equipamento) THEN
        SIGNAL SQLSTATE '45404' SET MESSAGE_TEXT = 'Equipamento não encontrado.';
    END IF;
    IF p_estado NOT IN ('otimo', 'bom', 'regular', 'ruim', 'inutilizavel') THEN
        SIGNAL SQLSTATE '45400' SET MESSAGE_TEXT = 'Estado de conservação inválido.';
    END IF;
    IF p_estado IN ('ruim', 'inutilizavel') AND COALESCE(TRIM(p_motivo), '') = '' THEN
        SIGNAL SQLSTATE '45400'
            SET MESSAGE_TEXT = 'Informe o motivo ao classificar o bem como ruim ou inutilizável.';
    END IF;
    IF fn_equipamento_em_movimentacao(p_id_equipamento) = 1 THEN
        SIGNAL SQLSTATE '45409'
            SET MESSAGE_TEXT = 'Bem em movimentação: conclua ou cancele antes de reavaliar.';
    END IF;

    SET @edufix_usuario = (SELECT CONCAT(nome, ' (id ', id_usuario, ')')
                           FROM usuario WHERE id_usuario = p_id_usuario);

    UPDATE equipamento SET estado_conservacao = p_estado WHERE id_equipamento = p_id_equipamento;

    SET @edufix_usuario = NULL;

    SELECT id_equipamento, estado_conservacao, status
    FROM equipamento WHERE id_equipamento = p_id_equipamento;
END $$


-- marcar_inativo / reativar: baixa e reativação do bem no patrimônio.

DROP PROCEDURE IF EXISTS sp_baixar_equipamento $$

CREATE PROCEDURE sp_baixar_equipamento(IN p_id_equipamento INT, IN p_id_usuario INT)
BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        SET @edufix_usuario = NULL;
        RESIGNAL;
    END;

    IF fn_admin_tem_permissao(p_id_usuario, 'gerenciar_patrimonio') = 0 THEN
        SIGNAL SQLSTATE '45403'
            SET MESSAGE_TEXT = 'Apenas administradores com permissão de patrimônio alteram bens.';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM equipamento WHERE id_equipamento = p_id_equipamento) THEN
        SIGNAL SQLSTATE '45404' SET MESSAGE_TEXT = 'Equipamento não encontrado.';
    END IF;

    SET @edufix_usuario = (SELECT CONCAT(nome, ' (id ', id_usuario, ')')
                           FROM usuario WHERE id_usuario = p_id_usuario);
    UPDATE equipamento SET status = 'inativo' WHERE id_equipamento = p_id_equipamento;
    SET @edufix_usuario = NULL;
END $$


DROP PROCEDURE IF EXISTS sp_reativar_equipamento $$

CREATE PROCEDURE sp_reativar_equipamento(IN p_id_equipamento INT, IN p_id_usuario INT)
BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        SET @edufix_usuario = NULL;
        RESIGNAL;
    END;

    IF fn_admin_tem_permissao(p_id_usuario, 'gerenciar_patrimonio') = 0 THEN
        SIGNAL SQLSTATE '45403'
            SET MESSAGE_TEXT = 'Apenas administradores com permissão de patrimônio alteram bens.';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM equipamento WHERE id_equipamento = p_id_equipamento) THEN
        SIGNAL SQLSTATE '45404' SET MESSAGE_TEXT = 'Equipamento não encontrado.';
    END IF;

    SET @edufix_usuario = (SELECT CONCAT(nome, ' (id ', id_usuario, ')')
                           FROM usuario WHERE id_usuario = p_id_usuario);
    UPDATE equipamento SET status = 'disponivel'
    WHERE id_equipamento = p_id_equipamento AND status = 'inativo';
    SET @edufix_usuario = NULL;
END $$


-- ============================================================
--  USUÁRIOS (método gerenciarUsuarios da classe Admin)
-- ============================================================

-- Desativa / reativa um usuário. Regras: o executor precisa da permissão
-- 'gerenciar_usuarios'; ninguém age sobre a própria conta; um admin só age sobre
-- admin de nível MENOR. A trigger do usuário ainda impede desativar quem tem chamado
-- em andamento e o último administrador ativo.

DROP PROCEDURE IF EXISTS sp_desativar_usuario $$

CREATE PROCEDURE sp_desativar_usuario(IN p_id_alvo INT, IN p_id_executor INT)
BEGIN
    IF fn_admin_tem_permissao(p_id_executor, 'gerenciar_usuarios') = 0 THEN
        SIGNAL SQLSTATE '45403'
            SET MESSAGE_TEXT = 'Apenas administradores com permissão de usuários executam esta ação.';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM usuario WHERE id_usuario = p_id_alvo) THEN
        SIGNAL SQLSTATE '45404' SET MESSAGE_TEXT = 'Usuário não encontrado.';
    END IF;
    IF p_id_alvo = p_id_executor THEN
        SIGNAL SQLSTATE '45403'
            SET MESSAGE_TEXT = 'Você não pode executar esta ação sobre a sua própria conta.';
    END IF;
    IF EXISTS (SELECT 1 FROM admin WHERE id_admin = p_id_alvo)
       AND (SELECT nivel_acesso FROM admin WHERE id_admin = p_id_alvo)
           >= (SELECT nivel_acesso FROM admin WHERE id_admin = p_id_executor) THEN
        SIGNAL SQLSTATE '45403'
            SET MESSAGE_TEXT = 'Só é possível gerenciar administradores de nível inferior.';
    END IF;

    UPDATE usuario SET ativo = FALSE WHERE id_usuario = p_id_alvo;
END $$


DROP PROCEDURE IF EXISTS sp_reativar_usuario $$

CREATE PROCEDURE sp_reativar_usuario(IN p_id_alvo INT, IN p_id_executor INT)
BEGIN
    IF fn_admin_tem_permissao(p_id_executor, 'gerenciar_usuarios') = 0 THEN
        SIGNAL SQLSTATE '45403'
            SET MESSAGE_TEXT = 'Apenas administradores com permissão de usuários executam esta ação.';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM usuario WHERE id_usuario = p_id_alvo) THEN
        SIGNAL SQLSTATE '45404' SET MESSAGE_TEXT = 'Usuário não encontrado.';
    END IF;
    IF p_id_alvo = p_id_executor THEN
        SIGNAL SQLSTATE '45403'
            SET MESSAGE_TEXT = 'Você não pode executar esta ação sobre a sua própria conta.';
    END IF;
    IF EXISTS (SELECT 1 FROM admin WHERE id_admin = p_id_alvo)
       AND (SELECT nivel_acesso FROM admin WHERE id_admin = p_id_alvo)
           >= (SELECT nivel_acesso FROM admin WHERE id_admin = p_id_executor) THEN
        SIGNAL SQLSTATE '45403'
            SET MESSAGE_TEXT = 'Só é possível gerenciar administradores de nível inferior.';
    END IF;

    UPDATE usuario SET ativo = TRUE WHERE id_usuario = p_id_alvo;
END $$


-- ============================================================
--  CONSULTAS DAS CLASSES SETOR E CATEGORIA (listarBens / contarBens)
-- ============================================================

-- Setor.listarBens: bens do setor, filtrados por status/categoria, ordenados por
-- nome | numero_patrimonio | data_aquisicao | estado_conservacao.
-- p_incluir_em_transito = 0 esconde os bens que estão saindo do setor.

DROP PROCEDURE IF EXISTS sp_listar_bens_setor $$

CREATE PROCEDURE sp_listar_bens_setor(
    IN p_id_setor            INT,
    IN p_status              VARCHAR(20),
    IN p_id_categoria        INT,
    IN p_incluir_em_transito TINYINT,
    IN p_ordenar_por         VARCHAR(30)
)
BEGIN
    IF NOT EXISTS (SELECT 1 FROM setor WHERE id_setor = p_id_setor) THEN
        SIGNAL SQLSTATE '45404' SET MESSAGE_TEXT = 'Setor não encontrado.';
    END IF;
    IF p_ordenar_por IS NOT NULL
       AND p_ordenar_por NOT IN ('nome', 'numero_patrimonio', 'data_aquisicao', 'estado_conservacao') THEN
        SIGNAL SQLSTATE '45400' SET MESSAGE_TEXT = 'ordenar_por inválido.';
    END IF;

    SELECT e.id_equipamento, e.nome, e.numero_patrimonio, c.nome AS categoria, e.status,
           e.estado_conservacao, e.data_aquisicao,
           fn_equipamento_em_movimentacao(e.id_equipamento) AS em_movimentacao
    FROM equipamento e
    LEFT JOIN categoria c ON c.id_categoria = e.id_categoria
    WHERE e.id_setor = p_id_setor
      AND (p_status IS NULL OR e.status = p_status)
      AND (p_id_categoria IS NULL OR e.id_categoria = p_id_categoria)
      AND (COALESCE(p_incluir_em_transito, 1) = 1
           OR fn_equipamento_em_movimentacao(e.id_equipamento) = 0)
    ORDER BY CASE WHEN p_ordenar_por = 'numero_patrimonio' THEN e.numero_patrimonio END,
             CASE WHEN p_ordenar_por = 'data_aquisicao' THEN e.data_aquisicao END,
             CASE WHEN p_ordenar_por = 'estado_conservacao' THEN fn_nivel_conservacao(e.estado_conservacao) END,
             e.nome;
END $$


-- Setor.contarBens: sem agrupamento devolve o total; com p_agrupar_por
-- ('status', 'categoria' ou 'estado_conservacao') devolve a quantidade por grupo.

DROP PROCEDURE IF EXISTS sp_contar_bens_setor $$

CREATE PROCEDURE sp_contar_bens_setor(IN p_id_setor INT, IN p_agrupar_por VARCHAR(30))
BEGIN
    IF NOT EXISTS (SELECT 1 FROM setor WHERE id_setor = p_id_setor) THEN
        SIGNAL SQLSTATE '45404' SET MESSAGE_TEXT = 'Setor não encontrado.';
    END IF;

    IF p_agrupar_por IS NULL OR p_agrupar_por = '' THEN
        SELECT fn_total_bens_setor(p_id_setor, NULL) AS total_bens;
    ELSEIF p_agrupar_por IN ('status', 'categoria', 'estado_conservacao') THEN
        SELECT CASE p_agrupar_por WHEN 'status'    THEN e.status
                                  WHEN 'categoria' THEN e.categoria
                                  ELSE e.estado_conservacao END AS grupo,
               COUNT(*) AS total_bens
        FROM equipamento e
        WHERE e.id_setor = p_id_setor
        GROUP BY grupo
        ORDER BY total_bens DESC, grupo;
    ELSE
        SIGNAL SQLSTATE '45400' SET MESSAGE_TEXT = 'agrupar_por inválido.';
    END IF;
END $$


-- Categoria.listarBens: bens da categoria (opcionalmente de um setor e/ou status),
-- já mostrando o setor de cada um.

DROP PROCEDURE IF EXISTS sp_listar_bens_categoria $$

CREATE PROCEDURE sp_listar_bens_categoria(
    IN p_id_categoria INT,
    IN p_id_setor     INT,
    IN p_status       VARCHAR(20)
)
BEGIN
    IF NOT EXISTS (SELECT 1 FROM categoria WHERE id_categoria = p_id_categoria) THEN
        SIGNAL SQLSTATE '45404' SET MESSAGE_TEXT = 'Categoria não encontrada.';
    END IF;

    SELECT s.nome AS setor, e.id_equipamento, e.nome, e.numero_patrimonio, e.status,
           e.estado_conservacao, e.data_aquisicao
    FROM equipamento e
    LEFT JOIN setor s ON s.id_setor = e.id_setor
    WHERE e.id_categoria = p_id_categoria
      AND (p_id_setor IS NULL OR e.id_setor = p_id_setor)
      AND (p_status IS NULL OR e.status = p_status)
    ORDER BY s.nome, e.nome;
END $$


-- ============================================================
--  RELATÓRIO OPERACIONAL (método emitirRelatorioOperacional da classe Admin)
-- ============================================================
-- Devolve 7 resultados: indicadores gerais, por status, por prioridade, por setor,
-- por categoria, bens com mais chamados e alertas. Só admin com permissão 'emitir_relatorios'.
-- p_inicio / p_fim (NULL = sem limite) filtram pela data de abertura do chamado.
-- p_taxa_hora: se informada, soma mão de obra (8h por dia trabalhado) ao custo.

DROP PROCEDURE IF EXISTS sp_relatorio_operacional $$

CREATE PROCEDURE sp_relatorio_operacional(
    IN p_inicio     DATE,
    IN p_fim        DATE,
    IN p_taxa_hora  DECIMAL(10, 2),
    IN p_id_usuario INT
)
BEGIN
    IF fn_admin_tem_permissao(p_id_usuario, 'emitir_relatorios') = 0 THEN
        SIGNAL SQLSTATE '45403'
            SET MESSAGE_TEXT = 'Apenas administradores com permissão de relatórios emitem este relatório.';
    END IF;

    DROP TEMPORARY TABLE IF EXISTS tmp_rel_chamados;
    CREATE TEMPORARY TABLE tmp_rel_chamados AS
    SELECT c.id_chamado, c.status, c.prioridade, c.id_equipamento, c.data_abertura,
           c.descricao_problema,
           TIMESTAMPDIFF(SECOND, c.data_abertura, COALESCE(c.data_fechamento, NOW())) / 3600 AS horas,
           (c.status <> 'cancelado'
            AND TIMESTAMPDIFF(SECOND, c.data_abertura, COALESCE(c.data_fechamento, NOW())) / 3600
                > fn_sla_horas(c.prioridade)) AS sla_estourado,
           s.nome AS setor,
           COALESCE(cat.nome, e.categoria) AS categoria,
           e.nome AS equipamento
    FROM chamado c
    LEFT JOIN equipamento e ON e.id_equipamento = c.id_equipamento
    LEFT JOIN setor s       ON s.id_setor = e.id_setor
    LEFT JOIN categoria cat ON cat.id_categoria = e.id_categoria
    WHERE (p_inicio IS NULL OR DATE(c.data_abertura) >= p_inicio)
      AND (p_fim    IS NULL OR DATE(c.data_abertura) <= p_fim);

    -- 1) indicadores gerais
    SELECT COUNT(*)                                                    AS total_chamados,
           COALESCE(SUM(status IN ('aberto', 'em_analise', 'em_execucao')), 0) AS em_andamento,
           COALESCE(SUM(status = 'concluido'), 0)                      AS concluidos,
           COALESCE(SUM(status = 'cancelado'), 0)                      AS cancelados,
           ROUND(100 * COALESCE(SUM(status = 'concluido'), 0) / NULLIF(COUNT(*), 0), 1)
                                                                       AS taxa_resolucao_pct,
           ROUND(AVG(CASE WHEN status = 'concluido' THEN horas END), 1) AS tempo_medio_resolucao_h,
           COALESCE(SUM(sla_estourado), 0)                             AS sla_estourados,
           ROUND(100 * (1 - COALESCE(SUM(sla_estourado), 0) / NULLIF(COUNT(*), 0)), 1)
                                                                       AS sla_cumprido_pct,
           (SELECT COUNT(*) FROM manutencao m
             WHERE m.id_chamado IN (SELECT id_chamado FROM tmp_rel_chamados)) AS manutencoes,
           (SELECT COALESCE(SUM(fn_custo_manutencao_total(m.id_manutencao, p_taxa_hora)), 0)
              FROM manutencao m
             WHERE m.id_chamado IN (SELECT id_chamado FROM tmp_rel_chamados)) AS custo_manutencao
    FROM tmp_rel_chamados;

    -- 2) por status
    SELECT status, COUNT(*) AS total
    FROM tmp_rel_chamados
    GROUP BY status
    ORDER BY FIELD(status, 'aberto', 'em_analise', 'em_execucao', 'concluido', 'cancelado');

    -- 3) por prioridade
    SELECT prioridade, COUNT(*) AS total, COALESCE(SUM(sla_estourado), 0) AS sla_estourados
    FROM tmp_rel_chamados
    GROUP BY prioridade
    ORDER BY FIELD(prioridade, 'critica', 'alta', 'media', 'baixa');

    -- 4) por setor
    SELECT COALESCE(setor, 'Sem setor') AS setor, COUNT(*) AS total
    FROM tmp_rel_chamados
    GROUP BY setor
    ORDER BY total DESC, setor;

    -- 5) por categoria
    SELECT COALESCE(categoria, 'Sem categoria') AS categoria, COUNT(*) AS total
    FROM tmp_rel_chamados
    GROUP BY categoria
    ORDER BY total DESC, categoria;

    -- 6) bens com mais chamados
    SELECT equipamento, COUNT(*) AS total_chamados
    FROM tmp_rel_chamados
    WHERE equipamento IS NOT NULL
    GROUP BY id_equipamento, equipamento
    ORDER BY total_chamados DESC, equipamento
    LIMIT 5;

    -- 7) alertas
    SELECT 'CRITICO' AS tipo,
           CONCAT('Chamado #', id_chamado, ' crítico em andamento (', COALESCE(equipamento, 'sem equipamento'), ')') AS alerta
    FROM tmp_rel_chamados
    WHERE prioridade = 'critica' AND status IN ('aberto', 'em_analise', 'em_execucao')
    UNION ALL
    SELECT 'SLA',
           CONCAT('Chamado #', id_chamado, ' passou do prazo de ', fn_sla_horas(prioridade), 'h (', ROUND(horas), 'h em aberto)')
    FROM tmp_rel_chamados
    WHERE sla_estourado = 1 AND status IN ('aberto', 'em_analise', 'em_execucao')
    UNION ALL
    SELECT 'REINCIDENCIA',
           CONCAT(equipamento, ' acumulou ', COUNT(*), ' chamados no período: avaliar substituição')
    FROM tmp_rel_chamados
    WHERE equipamento IS NOT NULL
    GROUP BY id_equipamento, equipamento
    HAVING COUNT(*) >= 3;

    DROP TEMPORARY TABLE IF EXISTS tmp_rel_chamados;
END $$


-- Linha do tempo completa de um equipamento: movimentações de setor, auditoria (log),
-- chamados e manutenções numa única lista cronológica.

DROP PROCEDURE IF EXISTS sp_historico_equipamento $$

CREATE PROCEDURE sp_historico_equipamento(IN p_id_equipamento INT)
BEGIN
    SELECT l.data_hora AS data_evento,
           CONCAT('Auditoria: ', l.acao) AS evento,
           CONCAT(COALESCE(l.valor_anterior, '-'), ' -> ', COALESCE(l.valor_novo, '-')) AS detalhe
    FROM log_patrimonio l
    WHERE l.id_equipamento = p_id_equipamento

    UNION ALL

    SELECT m.data_inicio,
           CONCAT('Movimentação #', m.id_movimentacao, ' (', m.situacao, ')'),
           CONCAT(COALESCE(so.nome, '-'), ' -> ', sd.nome)
    FROM movimentacao_equipamento m
    LEFT JOIN setor so ON so.id_setor = m.id_setor_origem
    INNER JOIN setor sd ON sd.id_setor = m.id_setor_destino
    WHERE m.id_equipamento = p_id_equipamento

    UNION ALL

    SELECT c.data_abertura,
           CONCAT('Chamado #', c.id_chamado, ' (', c.status, ')'),
           c.descricao_problema
    FROM chamado c
    WHERE c.id_equipamento = p_id_equipamento

    UNION ALL

    SELECT CAST(m.data_inicio AS DATETIME),
           CONCAT('Manutenção #', m.id_manutencao),
           CONCAT(COALESCE(m.descricao_servico, '-'), ' (R$ ', m.custo, ')')
    FROM manutencao m
    WHERE m.id_equipamento = p_id_equipamento

    ORDER BY data_evento;
END $$

DELIMITER ;
