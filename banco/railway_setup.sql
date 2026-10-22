-- ============================================================
-- EduFix - Setup completo para Railway
-- Ordem: Estrutura → Functions → Procedures
-- ============================================================

SET FOREIGN_KEY_CHECKS = 0;

DROP TABLE IF EXISTS historico_status_chamado;
DROP TABLE IF EXISTS manutencao;
DROP TABLE IF EXISTS chamado;
DROP TABLE IF EXISTS admin;
DROP TABLE IF EXISTS equipamento;
DROP TABLE IF EXISTS usuario;

CREATE TABLE usuario (
    id_usuario      INT           NOT NULL AUTO_INCREMENT,
    nome            VARCHAR(100)  NOT NULL,
    senha           VARCHAR(255)  NOT NULL,
    ativo           BOOLEAN       NOT NULL DEFAULT TRUE,
    data_cadastro   DATE          NOT NULL DEFAULT (CURRENT_DATE),
    email           VARCHAR(100)  NOT NULL,
    telefone        VARCHAR(20),
    cpf             VARCHAR(14)   NOT NULL,
    ultimo_login    DATETIME,
    data_nascimento DATE,
    tipo_usuario    ENUM('usuario', 'admin') NOT NULL DEFAULT 'usuario',

    CONSTRAINT pk_usuario        PRIMARY KEY (id_usuario),
    CONSTRAINT uq_usuario_email  UNIQUE (email),
    CONSTRAINT uq_usuario_cpf    UNIQUE (cpf)
);

CREATE TABLE admin (
    id_admin        INT   NOT NULL,
    nivel_acesso    INT   NOT NULL DEFAULT 1,
    permissoes      TEXT,

    CONSTRAINT pk_admin         PRIMARY KEY (id_admin),
    CONSTRAINT fk_admin_usuario FOREIGN KEY (id_admin)
        REFERENCES usuario (id_usuario)
        ON DELETE CASCADE
        ON UPDATE CASCADE,
    CONSTRAINT chk_admin_nivel  CHECK (nivel_acesso BETWEEN 1 AND 5)
);

CREATE TABLE equipamento (
    id_equipamento      INT           NOT NULL AUTO_INCREMENT,
    nome                VARCHAR(100)  NOT NULL,
    descricao           VARCHAR(255),
    estado_conservacao  ENUM('otimo', 'bom', 'regular', 'ruim', 'inutilizavel')
                                      NOT NULL DEFAULT 'bom',
    localizacao         VARCHAR(100),
    numero_patrimonio   VARCHAR(50),
    categoria           VARCHAR(50),
    status              ENUM('disponivel', 'em_uso', 'em_manutencao', 'inativo')
                                      NOT NULL DEFAULT 'disponivel',
    data_aquisicao      DATE,

    CONSTRAINT pk_equipamento               PRIMARY KEY (id_equipamento),
    CONSTRAINT uq_equipamento_patrimonio    UNIQUE (numero_patrimonio)
);

CREATE TABLE chamado (
    id_chamado          INT       NOT NULL AUTO_INCREMENT,
    id_usuario          INT       NOT NULL,
    id_equipamento      INT,
    data_abertura       DATETIME  NOT NULL DEFAULT CURRENT_TIMESTAMP,
    data_fechamento     DATETIME,
    status              ENUM('aberto', 'em_analise', 'em_execucao', 'concluido', 'cancelado')
                                  NOT NULL DEFAULT 'aberto',
    prioridade          ENUM('baixa', 'media', 'alta', 'critica')
                                  NOT NULL DEFAULT 'media',
    descricao_problema  TEXT      NOT NULL,
    observacoes         TEXT,

    CONSTRAINT pk_chamado               PRIMARY KEY (id_chamado),
    CONSTRAINT fk_chamado_usuario       FOREIGN KEY (id_usuario)
        REFERENCES usuario (id_usuario)
        ON DELETE RESTRICT
        ON UPDATE CASCADE,
    CONSTRAINT fk_chamado_equipamento   FOREIGN KEY (id_equipamento)
        REFERENCES equipamento (id_equipamento)
        ON DELETE SET NULL
        ON UPDATE CASCADE,
    CONSTRAINT chk_chamado_datas        CHECK (
        data_fechamento IS NULL OR data_fechamento >= data_abertura
    )
);

CREATE TABLE manutencao (
    id_manutencao           INT             NOT NULL AUTO_INCREMENT,
    id_chamado              INT             NOT NULL,
    id_equipamento          INT             NOT NULL,
    data_inicio             DATE            NOT NULL,
    data_fim                DATE,
    descricao_servico       TEXT,
    tecnico_responsavel     VARCHAR(100),
    custo                   DECIMAL(10, 2)  NOT NULL DEFAULT 0.00,

    CONSTRAINT pk_manutencao                PRIMARY KEY (id_manutencao),
    CONSTRAINT fk_manutencao_chamado        FOREIGN KEY (id_chamado)
        REFERENCES chamado (id_chamado)
        ON DELETE RESTRICT
        ON UPDATE CASCADE,
    CONSTRAINT fk_manutencao_equipamento    FOREIGN KEY (id_equipamento)
        REFERENCES equipamento (id_equipamento)
        ON DELETE RESTRICT
        ON UPDATE CASCADE,
    CONSTRAINT chk_manutencao_datas         CHECK (
        data_fim IS NULL OR data_fim >= data_inicio
    ),
    CONSTRAINT chk_manutencao_custo         CHECK (custo >= 0)
);

CREATE TABLE historico_status_chamado (
    id_historico    INT       NOT NULL AUTO_INCREMENT,
    id_chamado      INT       NOT NULL,
    id_usuario      INT       NOT NULL,
    status_anterior ENUM('aberto', 'em_analise', 'em_execucao', 'concluido', 'cancelado'),
    status_novo     ENUM('aberto', 'em_analise', 'em_execucao', 'concluido', 'cancelado')
                              NOT NULL,
    data_alteracao  DATETIME  NOT NULL DEFAULT CURRENT_TIMESTAMP,
    observacao      TEXT,

    CONSTRAINT pk_historico             PRIMARY KEY (id_historico),
    CONSTRAINT fk_historico_chamado     FOREIGN KEY (id_chamado)
        REFERENCES chamado (id_chamado)
        ON DELETE CASCADE
        ON UPDATE CASCADE,
    CONSTRAINT fk_historico_usuario     FOREIGN KEY (id_usuario)
        REFERENCES usuario (id_usuario)
        ON DELETE RESTRICT
        ON UPDATE CASCADE
);

SET FOREIGN_KEY_CHECKS = 1;

-- ============================================================
-- FUNCTIONS
-- ============================================================

DELIMITER $$

DROP FUNCTION IF EXISTS fn_custo_total_manutencao $$
CREATE FUNCTION fn_custo_total_manutencao(p_id_equipamento INT)
RETURNS DECIMAL(10, 2)
DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_total DECIMAL(10, 2);
    SELECT COALESCE(SUM(custo), 0.00) INTO v_total
    FROM manutencao WHERE id_equipamento = p_id_equipamento;
    RETURN v_total;
END $$

DROP FUNCTION IF EXISTS fn_total_chamados_abertos $$
CREATE FUNCTION fn_total_chamados_abertos(p_id_usuario INT)
RETURNS INT
DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_total INT;
    SELECT COUNT(*) INTO v_total FROM chamado
    WHERE id_usuario = p_id_usuario AND status = 'aberto';
    RETURN v_total;
END $$

DROP FUNCTION IF EXISTS fn_verificar_disponibilidade $$
CREATE FUNCTION fn_verificar_disponibilidade(p_id_equipamento INT)
RETURNS VARCHAR(20)
DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_status VARCHAR(50);
    SELECT status INTO v_status FROM equipamento
    WHERE id_equipamento = p_id_equipamento;
    IF v_status = 'disponivel' THEN RETURN 'Disponível';
    ELSE RETURN 'Indisponível';
    END IF;
END $$

DROP FUNCTION IF EXISTS fn_tempo_resolucao_chamado $$
CREATE FUNCTION fn_tempo_resolucao_chamado(p_id_chamado INT)
RETURNS INT
DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_abertura  DATETIME;
    DECLARE v_fechamento DATETIME;
    SELECT data_abertura, data_fechamento INTO v_abertura, v_fechamento
    FROM chamado WHERE id_chamado = p_id_chamado;
    IF v_fechamento IS NULL THEN RETURN DATEDIFF(NOW(), v_abertura);
    END IF;
    RETURN DATEDIFF(v_fechamento, v_abertura);
END $$

DROP FUNCTION IF EXISTS fn_total_chamados_equipamento $$
CREATE FUNCTION fn_total_chamados_equipamento(p_id_equipamento INT)
RETURNS INT
DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_total INT;
    SELECT COUNT(*) INTO v_total FROM chamado
    WHERE id_equipamento = p_id_equipamento;
    RETURN v_total;
END $$

-- ============================================================
-- PROCEDURES
-- ============================================================

DROP PROCEDURE IF EXISTS sp_resumo_equipamentos $$
CREATE PROCEDURE sp_resumo_equipamentos(IN p_categoria VARCHAR(50))
BEGIN
    SELECT
        e.id_equipamento,
        e.nome                                          AS nome_equipamento,
        e.categoria,
        e.localizacao,
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
    GROUP BY e.id_equipamento, e.nome, e.categoria, e.localizacao, e.estado_conservacao
    HAVING fn_total_chamados_equipamento(e.id_equipamento) > 0 OR COUNT(m.id_manutencao) > 0
    ORDER BY custo_total_manutencao DESC, total_chamados DESC;
END $$

DROP PROCEDURE IF EXISTS sp_chamados_detalhados $$
CREATE PROCEDURE sp_chamados_detalhados(IN p_status VARCHAR(20))
BEGIN
    SELECT
        c.id_chamado,
        c.status,
        c.prioridade,
        c.data_abertura,
        c.data_fechamento,
        fn_tempo_resolucao_chamado(c.id_chamado)    AS dias_resolucao,
        c.descricao_problema                        AS descricao,
        u.nome                                      AS nome_usuario,
        u.email                                     AS email_usuario,
        e.nome                                      AS nome_equipamento,
        e.localizacao                               AS localizacao_equipamento,
        e.categoria                                 AS categoria_equipamento,
        COUNT(m.id_manutencao)                      AS total_manutencoes
    FROM chamado c
    INNER JOIN usuario     u ON c.id_usuario     = u.id_usuario
    LEFT  JOIN equipamento e ON c.id_equipamento = e.id_equipamento
    LEFT  JOIN manutencao  m ON c.id_chamado     = m.id_chamado
    WHERE (p_status IS NULL OR c.status = p_status)
    GROUP BY c.id_chamado, c.status, c.prioridade, c.data_abertura,
             c.data_fechamento, c.descricao_problema, u.nome, u.email,
             e.nome, e.localizacao, e.categoria
    ORDER BY FIELD(c.prioridade, 'critica', 'alta', 'media', 'baixa'), c.data_abertura DESC;
END $$

DROP PROCEDURE IF EXISTS sp_desempenho_usuarios $$
CREATE PROCEDURE sp_desempenho_usuarios()
BEGIN
    SELECT
        u.id_usuario,
        u.nome                                          AS nome_usuario,
        u.email,
        u.tipo_usuario                                  AS tipo,
        COUNT(DISTINCT c.id_chamado)                    AS total_chamados_criados,
        fn_total_chamados_abertos(u.id_usuario)         AS chamados_ainda_abertos,
        COUNT(DISTINCT h.id_historico)                  AS total_interacoes_status,
        MAX(c.data_abertura)                            AS ultimo_chamado_criado
    FROM usuario u
    LEFT JOIN chamado                  c ON u.id_usuario = c.id_usuario
    LEFT JOIN historico_status_chamado h ON u.id_usuario = h.id_usuario
    WHERE u.ativo = TRUE
    GROUP BY u.id_usuario, u.nome, u.email, u.tipo_usuario
    HAVING COUNT(DISTINCT c.id_chamado) > 0
    ORDER BY total_chamados_criados DESC, total_interacoes_status DESC;
END $$

DELIMITER ;

SELECT 'EduFix setup concluido com sucesso!' AS resultado;
