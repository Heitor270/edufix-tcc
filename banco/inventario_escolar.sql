
--  Etapa 1 - Stored Procedure: Criação da Estrutura do Banco (v3: + setor, categoria,
--  movimentacao_equipamento e log_patrimonio)

DROP DATABASE IF EXISTS inventario_escolar;
CREATE DATABASE inventario_escolar
    CHARACTER SET utf8mb4
    COLLATE utf8mb4_unicode_ci;

USE inventario_escolar;

DELIMITER $$

DROP PROCEDURE IF EXISTS criar_estrutura_banco $$

CREATE PROCEDURE criar_estrutura_banco()
BEGIN

    SET FOREIGN_KEY_CHECKS = 0;

    DROP TABLE IF EXISTS movimentacao_equipamento;
    DROP TABLE IF EXISTS log_patrimonio;
    DROP TABLE IF EXISTS historico_status_chamado;
    DROP TABLE IF EXISTS manutencao;
    DROP TABLE IF EXISTS chamado;
    DROP TABLE IF EXISTS admin;
    DROP TABLE IF EXISTS equipamento;
    DROP TABLE IF EXISTS setor;
    DROP TABLE IF EXISTS categoria;
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

    -- Setor (sala, laboratório, secretaria...) e Categoria (tipo do bem): classes
    -- Setor e Categoria do diagrama. Um setor/categoria tem N equipamentos.
    CREATE TABLE setor (
        id_setor    INT           NOT NULL AUTO_INCREMENT,
        nome        VARCHAR(100)  NOT NULL,

        CONSTRAINT pk_setor       PRIMARY KEY (id_setor),
        CONSTRAINT uq_setor_nome  UNIQUE (nome)
    );

    CREATE TABLE categoria (
        id_categoria INT          NOT NULL AUTO_INCREMENT,
        nome         VARCHAR(50)  NOT NULL,

        CONSTRAINT pk_categoria       PRIMARY KEY (id_categoria),
        CONSTRAINT uq_categoria_nome  UNIQUE (nome)
    );

    INSERT INTO categoria (nome) VALUES
        ('Informatica'), ('Mobiliario'), ('Climatizacao'), ('Eletrodomestico'), ('Outro');

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
        -- As colunas texto (localizacao / categoria) continuam existindo e são o que a
        -- aplicação grava; as colunas id_* abaixo são mantidas pelo BANCO (trigger
        -- trg_equipamento_before_insert/update), ligando o bem às tabelas setor e categoria.
        id_setor            INT,
        id_categoria        INT,

        CONSTRAINT pk_equipamento               PRIMARY KEY (id_equipamento),
        CONSTRAINT uq_equipamento_patrimonio    UNIQUE (numero_patrimonio),
        CONSTRAINT fk_equipamento_setor         FOREIGN KEY (id_setor)
            REFERENCES setor (id_setor)
            ON DELETE RESTRICT
            ON UPDATE CASCADE,
        CONSTRAINT fk_equipamento_categoria     FOREIGN KEY (id_categoria)
            REFERENCES categoria (id_categoria)
            ON DELETE RESTRICT
            ON UPDATE CASCADE
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

    -- Movimentação do bem entre setores: informa se o bem está "em trânsito".
    -- A coluna virtual chave_aberta + índice único garantem, no próprio banco,
    -- que um bem só pode ter UMA movimentação em andamento por vez.
    CREATE TABLE movimentacao_equipamento (
        id_movimentacao   INT       NOT NULL AUTO_INCREMENT,
        id_equipamento    INT       NOT NULL,
        id_setor_origem   INT,
        id_setor_destino  INT       NOT NULL,
        id_usuario        INT       NOT NULL,
        data_inicio       DATETIME  NOT NULL DEFAULT CURRENT_TIMESTAMP,
        data_conclusao    DATETIME,
        situacao          ENUM('em_transito', 'concluida', 'cancelada')
                                    NOT NULL DEFAULT 'em_transito',
        observacao        VARCHAR(255),
        chave_aberta      INT AS (CASE WHEN situacao = 'em_transito' THEN id_equipamento END) VIRTUAL,

        CONSTRAINT pk_movimentacao          PRIMARY KEY (id_movimentacao),
        CONSTRAINT uq_movimentacao_aberta   UNIQUE (chave_aberta),
        CONSTRAINT fk_mov_equipamento       FOREIGN KEY (id_equipamento)
            REFERENCES equipamento (id_equipamento)
            ON DELETE CASCADE
            ON UPDATE CASCADE,
        CONSTRAINT fk_mov_setor_origem      FOREIGN KEY (id_setor_origem)
            REFERENCES setor (id_setor)
            ON DELETE RESTRICT
            ON UPDATE CASCADE,
        CONSTRAINT fk_mov_setor_destino     FOREIGN KEY (id_setor_destino)
            REFERENCES setor (id_setor)
            ON DELETE RESTRICT
            ON UPDATE CASCADE,
        CONSTRAINT fk_mov_usuario           FOREIGN KEY (id_usuario)
            REFERENCES usuario (id_usuario)
            ON DELETE RESTRICT
            ON UPDATE CASCADE,
        CONSTRAINT chk_mov_datas            CHECK (
            data_conclusao IS NULL OR data_conclusao >= data_inicio
        )
    );

    -- Auditoria do patrimônio (classe LogPatrimonio). Sem chave estrangeira de
    -- propósito: o registro precisa sobreviver à exclusão do equipamento.
    CREATE TABLE log_patrimonio (
        id_log           INT           NOT NULL AUTO_INCREMENT,
        id_equipamento   INT           NOT NULL,
        nome_equipamento VARCHAR(100)  NOT NULL,
        acao             ENUM('CADASTRO', 'TRANSFERENCIA', 'MUDANCA_STATUS',
                              'MUDANCA_CONSERVACAO', 'EXCLUSAO') NOT NULL,
        valor_anterior   VARCHAR(100),
        valor_novo       VARCHAR(100),
        usuario_banco    VARCHAR(100)  NOT NULL,
        data_hora        DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,

        CONSTRAINT pk_log_patrimonio PRIMARY KEY (id_log),
        INDEX idx_log_equipamento (id_equipamento),
        INDEX idx_log_data (data_hora)
    );

    SET FOREIGN_KEY_CHECKS = 1;

    SELECT 'Estrutura do banco EduFix criada com sucesso!' AS resultado;

END $$

DELIMITER ;

CALL criar_estrutura_banco();