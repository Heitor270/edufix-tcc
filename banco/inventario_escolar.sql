
--  Etapa 1 - Stored Procedure: Criação da Estrutura do Banco

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

    SELECT 'Estrutura do banco EduFix criada com sucesso!' AS resultado;

END $$

DELIMITER ;

CALL criar_estrutura_banco();