-- ============================================================
--  EduFix / inventario_escolar
--  Tópico 6 - Triggers (regras automáticas do banco)  - v3
-- ============================================================
--  Códigos de erro usados nos SIGNAL (o backend converte em HTTP):
--    45400 dado inválido | 45403 sem permissão | 45404 não encontrado
--    45409 conflito com o estado atual | 45422 regra de negócio violada
--
--  A tabela log_patrimonio agora é criada em inventario_escolar.sql.
--
--  MODO IMPORTAÇÃO: para carregar dados antigos ou fictícios (CPF de teste, chamado
--  com descrição curta, manutenção em chamado já concluído...), ligue a variável
--  de sessão e desligue no fim. Ela só afasta as VALIDAÇÕES de cadastro; o resto
--  (normalização, vínculo com setor/categoria, auditoria) continua funcionando:
--      SET @edufix_importacao = 1;
--      ... INSERTs ...
--      SET @edufix_importacao = 0;
-- ============================================================

USE inventario_escolar;

DELIMITER $$

-- ============================================================
--  CHAMADO
-- ============================================================

-- ANTES DE ATUALIZAR o chamado:
--   * data_fechamento: concluido / cancelado -> agora (se ainda vazia);
--                      qualquer outro status -> NULL (chamado reaberto).
--   * O equipamento de um chamado que já tem manutenção não pode ser trocado:
--     a manutenção pertence ao chamado, e o equipamento vem pelo chamado.

DROP TRIGGER IF EXISTS trg_chamado_data_fechamento $$

CREATE TRIGGER trg_chamado_data_fechamento
BEFORE UPDATE ON chamado
FOR EACH ROW
BEGIN
    IF NEW.status IN ('concluido', 'cancelado') THEN
        IF NEW.data_fechamento IS NULL THEN
            SET NEW.data_fechamento = NOW();
        END IF;
    ELSE
        SET NEW.data_fechamento = NULL;
    END IF;

    IF NOT (OLD.id_equipamento <=> NEW.id_equipamento)
       AND EXISTS (SELECT 1 FROM manutencao WHERE id_chamado = OLD.id_chamado) THEN
        SIGNAL SQLSTATE '45409'
            SET MESSAGE_TEXT = 'Chamado com manutenção registrada não pode trocar de equipamento.';
    END IF;
END $$


-- ANTES DE INSERIR o chamado (método registrarAbertura da classe Chamado):
--   * descrição com pelo menos 10 caracteres;
--   * usuário precisa estar ativo;
--   * chamado em andamento exige equipamento ativo (erro 45422);
--   * o mesmo usuário não pode ter 2 chamados em andamento para o mesmo equipamento.

DROP TRIGGER IF EXISTS trg_chamado_valida_equipamento $$

CREATE TRIGGER trg_chamado_valida_equipamento
BEFORE INSERT ON chamado
FOR EACH ROW
BEGIN
    SET NEW.descricao_problema = TRIM(NEW.descricao_problema);

    IF COALESCE(@edufix_importacao, 0) = 0 THEN
        IF CHAR_LENGTH(NEW.descricao_problema) < 10 THEN
            SIGNAL SQLSTATE '45400'
                SET MESSAGE_TEXT = 'Descreva o problema com pelo menos 10 caracteres.';
        END IF;

        IF NOT EXISTS (SELECT 1 FROM usuario WHERE id_usuario = NEW.id_usuario AND ativo = TRUE) THEN
            SIGNAL SQLSTATE '45403'
                SET MESSAGE_TEXT = 'Usuário inativo (ou inexistente) não pode abrir chamado.';
        END IF;

        IF NEW.id_equipamento IS NOT NULL
           AND NEW.status IN ('aberto', 'em_analise', 'em_execucao') THEN

            IF fn_equipamento_inativo(NEW.id_equipamento) = 1 THEN
                SIGNAL SQLSTATE '45422'
                    SET MESSAGE_TEXT = 'Não é possível abrir chamado para um equipamento inativo.';
            END IF;

            IF EXISTS (SELECT 1
                       FROM chamado
                       WHERE id_usuario     = NEW.id_usuario
                         AND id_equipamento = NEW.id_equipamento
                         AND status IN ('aberto', 'em_analise', 'em_execucao')) THEN
                SIGNAL SQLSTATE '45409'
                    SET MESSAGE_TEXT = 'Você já tem um chamado em andamento para este equipamento.';
            END IF;
        END IF;
    END IF;
END $$


-- DEPOIS DE INSERIR o chamado: grava sozinho o 1º registro do histórico
-- (status_anterior NULL -> status inicial), igual ao primeiro item da lista
-- historico da classe Chamado.

DROP TRIGGER IF EXISTS trg_chamado_after_insert $$

CREATE TRIGGER trg_chamado_after_insert
AFTER INSERT ON chamado
FOR EACH ROW
BEGIN
    IF COALESCE(@edufix_importacao, 0) = 0 THEN
        INSERT INTO historico_status_chamado
            (id_chamado, id_usuario, status_anterior, status_novo, observacao)
        VALUES
            (NEW.id_chamado, NEW.id_usuario, NULL, NEW.status, 'Chamado aberto');
    END IF;
END $$


-- DEPOIS DE ATUALIZAR o chamado: se ele foi encerrado (concluído/cancelado),
-- reacerta o equipamento (volta de 'em_manutencao' e, se o bem é inutilizável e
-- não tem mais chamado ativo, é baixado).

DROP TRIGGER IF EXISTS trg_chamado_after_update $$

CREATE TRIGGER trg_chamado_after_update
AFTER UPDATE ON chamado
FOR EACH ROW
BEGIN
    IF OLD.status <> NEW.status
       AND NEW.status IN ('concluido', 'cancelado')
       AND NEW.id_equipamento IS NOT NULL THEN
        CALL sp_sincronizar_equipamento(NEW.id_equipamento);
    END IF;
END $$


-- ============================================================
--  HISTÓRICO e LOG: registros de auditoria são imutáveis
-- ============================================================

DROP TRIGGER IF EXISTS trg_historico_imutavel $$

CREATE TRIGGER trg_historico_imutavel
BEFORE UPDATE ON historico_status_chamado
FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45409'
        SET MESSAGE_TEXT = 'O histórico de status é um registro de auditoria e não pode ser alterado.';
END $$


DROP TRIGGER IF EXISTS trg_log_patrimonio_imutavel_update $$

CREATE TRIGGER trg_log_patrimonio_imutavel_update
BEFORE UPDATE ON log_patrimonio
FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45409'
        SET MESSAGE_TEXT = 'O log do patrimônio é um registro de auditoria e não pode ser alterado.';
END $$


DROP TRIGGER IF EXISTS trg_log_patrimonio_imutavel_delete $$

CREATE TRIGGER trg_log_patrimonio_imutavel_delete
BEFORE DELETE ON log_patrimonio
FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45409'
        SET MESSAGE_TEXT = 'O log do patrimônio é um registro de auditoria e não pode ser apagado.';
END $$


-- ============================================================
--  USUÁRIO e ADMIN
-- ============================================================

-- Padroniza e VALIDA os dados do usuário no cadastro (classe Usuario):
-- nome sem espaços sobrando (mín. 3 letras), e-mail em minúsculas e no formato certo,
-- CPF com dígitos verificadores válidos e data de nascimento possível.

DROP TRIGGER IF EXISTS trg_usuario_normaliza_insert $$

CREATE TRIGGER trg_usuario_normaliza_insert
BEFORE INSERT ON usuario
FOR EACH ROW
BEGIN
    SET NEW.nome = REGEXP_REPLACE(TRIM(NEW.nome), '[[:space:]]+', ' ');
    IF NEW.email IS NOT NULL THEN
        SET NEW.email = LOWER(TRIM(NEW.email));
    END IF;

    IF COALESCE(@edufix_importacao, 0) = 0 THEN
        IF CHAR_LENGTH(NEW.nome) < 3 THEN
            SIGNAL SQLSTATE '45400' SET MESSAGE_TEXT = 'Nome deve ter pelo menos 3 caracteres.';
        END IF;
        IF fn_validar_email(NEW.email) = 0 THEN
            SIGNAL SQLSTATE '45400' SET MESSAGE_TEXT = 'E-mail inválido. Use o formato nome@dominio.com.';
        END IF;
        IF fn_validar_cpf(NEW.cpf) = 0 THEN
            SIGNAL SQLSTATE '45400' SET MESSAGE_TEXT = 'CPF inválido.';
        END IF;
        IF NEW.data_nascimento IS NOT NULL
           AND (NEW.data_nascimento > CURDATE() OR NEW.data_nascimento < (CURDATE() - INTERVAL 120 YEAR)) THEN
            SIGNAL SQLSTATE '45400' SET MESSAGE_TEXT = 'Data de nascimento inválida.';
        END IF;
    END IF;
END $$


-- Na ALTERAÇÃO valida só o que mudou (assim o login, que atualiza ultimo_login,
-- nunca é barrado por um dado antigo). Regras extras (métodos desativar/gerenciarUsuarios):
--   * não desativa usuário que tem chamado em andamento;
--   * não deixa o sistema sem nenhum administrador ativo.

DROP TRIGGER IF EXISTS trg_usuario_normaliza_update $$

CREATE TRIGGER trg_usuario_normaliza_update
BEFORE UPDATE ON usuario
FOR EACH ROW
BEGIN
    SET NEW.nome = REGEXP_REPLACE(TRIM(NEW.nome), '[[:space:]]+', ' ');
    IF NEW.email IS NOT NULL THEN
        SET NEW.email = LOWER(TRIM(NEW.email));
    END IF;

    IF NOT (OLD.nome <=> NEW.nome) AND CHAR_LENGTH(NEW.nome) < 3 THEN
        SIGNAL SQLSTATE '45400' SET MESSAGE_TEXT = 'Nome deve ter pelo menos 3 caracteres.';
    END IF;
    IF NOT (OLD.email <=> NEW.email) AND fn_validar_email(NEW.email) = 0 THEN
        SIGNAL SQLSTATE '45400' SET MESSAGE_TEXT = 'E-mail inválido. Use o formato nome@dominio.com.';
    END IF;
    IF NOT (OLD.cpf <=> NEW.cpf) AND fn_validar_cpf(NEW.cpf) = 0 THEN
        SIGNAL SQLSTATE '45400' SET MESSAGE_TEXT = 'CPF inválido.';
    END IF;
    IF NOT (OLD.data_nascimento <=> NEW.data_nascimento) AND NEW.data_nascimento IS NOT NULL
       AND (NEW.data_nascimento > CURDATE() OR NEW.data_nascimento < (CURDATE() - INTERVAL 120 YEAR)) THEN
        SIGNAL SQLSTATE '45400' SET MESSAGE_TEXT = 'Data de nascimento inválida.';
    END IF;

    IF OLD.ativo = TRUE AND NEW.ativo = FALSE
       AND EXISTS (SELECT 1 FROM chamado
                   WHERE id_usuario = OLD.id_usuario
                     AND status IN ('aberto', 'em_analise', 'em_execucao')) THEN
        SIGNAL SQLSTATE '45409'
            SET MESSAGE_TEXT = 'Usuário com chamado em andamento não pode ser desativado.';
    END IF;

    IF OLD.tipo_usuario = 'admin' AND OLD.ativo = TRUE
       AND (NEW.tipo_usuario <> 'admin' OR NEW.ativo = FALSE)
       AND NOT EXISTS (SELECT 1 FROM usuario
                       WHERE tipo_usuario = 'admin' AND ativo = TRUE
                         AND id_usuario <> OLD.id_usuario) THEN
        SIGNAL SQLSTATE '45409'
            SET MESSAGE_TEXT = 'O sistema precisa de pelo menos um administrador ativo.';
    END IF;
END $$


-- A tabela admin só aceita quem é usuário do tipo 'admin'; permissões são
-- gravadas em minúsculas e sem espaços (ex.: "gerenciar_chamados,emitir_relatorios").

DROP TRIGGER IF EXISTS trg_admin_valida_insert $$

CREATE TRIGGER trg_admin_valida_insert
BEFORE INSERT ON admin
FOR EACH ROW
BEGIN
    IF NOT EXISTS (SELECT 1 FROM usuario
                   WHERE id_usuario = NEW.id_admin AND tipo_usuario = 'admin') THEN
        SIGNAL SQLSTATE '45422'
            SET MESSAGE_TEXT = 'Só um usuário do tipo admin pode ter nível de acesso.';
    END IF;
    SET NEW.permissoes = LOWER(REPLACE(COALESCE(NEW.permissoes, ''), ' ', ''));
END $$


DROP TRIGGER IF EXISTS trg_admin_valida_update $$

CREATE TRIGGER trg_admin_valida_update
BEFORE UPDATE ON admin
FOR EACH ROW
BEGIN
    SET NEW.permissoes = LOWER(REPLACE(COALESCE(NEW.permissoes, ''), ' ', ''));
END $$


-- ============================================================
--  SETOR e CATEGORIA
-- ============================================================

DROP TRIGGER IF EXISTS trg_setor_valida $$

CREATE TRIGGER trg_setor_valida
BEFORE INSERT ON setor
FOR EACH ROW
BEGIN
    SET NEW.nome = REGEXP_REPLACE(TRIM(NEW.nome), '[[:space:]]+', ' ');
    IF CHAR_LENGTH(NEW.nome) < 2 THEN
        SIGNAL SQLSTATE '45400' SET MESSAGE_TEXT = 'Nome do setor deve ter pelo menos 2 caracteres.';
    END IF;
END $$


DROP TRIGGER IF EXISTS trg_setor_bloqueia_exclusao $$

CREATE TRIGGER trg_setor_bloqueia_exclusao
BEFORE DELETE ON setor
FOR EACH ROW
BEGIN
    IF EXISTS (SELECT 1 FROM equipamento WHERE id_setor = OLD.id_setor) THEN
        SIGNAL SQLSTATE '45409'
            SET MESSAGE_TEXT = 'Setor com bens cadastrados não pode ser excluído. Transfira os bens antes.';
    END IF;
END $$


DROP TRIGGER IF EXISTS trg_categoria_valida $$

CREATE TRIGGER trg_categoria_valida
BEFORE INSERT ON categoria
FOR EACH ROW
BEGIN
    SET NEW.nome = REGEXP_REPLACE(TRIM(NEW.nome), '[[:space:]]+', ' ');
    IF CHAR_LENGTH(NEW.nome) < 2 THEN
        SIGNAL SQLSTATE '45400' SET MESSAGE_TEXT = 'Nome da categoria deve ter pelo menos 2 caracteres.';
    END IF;
END $$


DROP TRIGGER IF EXISTS trg_categoria_bloqueia_exclusao $$

CREATE TRIGGER trg_categoria_bloqueia_exclusao
BEFORE DELETE ON categoria
FOR EACH ROW
BEGIN
    IF EXISTS (SELECT 1 FROM equipamento WHERE id_categoria = OLD.id_categoria) THEN
        SIGNAL SQLSTATE '45409'
            SET MESSAGE_TEXT = 'Categoria com bens cadastrados não pode ser excluída.';
    END IF;
END $$


-- ============================================================
--  EQUIPAMENTO
-- ============================================================

-- ANTES DE INSERIR o bem: limpa os textos, liga o bem às tabelas setor e categoria
-- (criando o setor/categoria se ainda não existir) e valida os dados.
-- O setor é o que vem antes de " - " na localização ('Secretaria - sala 2' -> 'Secretaria').

DROP TRIGGER IF EXISTS trg_equipamento_before_insert $$

CREATE TRIGGER trg_equipamento_before_insert
BEFORE INSERT ON equipamento
FOR EACH ROW
BEGIN
    SET NEW.nome        = REGEXP_REPLACE(TRIM(NEW.nome), '[[:space:]]+', ' ');
    SET NEW.localizacao = NULLIF(TRIM(NEW.localizacao), '');
    SET NEW.categoria   = COALESCE(NULLIF(TRIM(NEW.categoria), ''), 'Outro');
    IF NEW.numero_patrimonio IS NOT NULL THEN
        SET NEW.numero_patrimonio = TRIM(NEW.numero_patrimonio);
    END IF;

    IF CHAR_LENGTH(NEW.nome) < 2 THEN
        SIGNAL SQLSTATE '45400' SET MESSAGE_TEXT = 'Nome do equipamento muito curto.';
    END IF;
    IF COALESCE(@edufix_importacao, 0) = 0 THEN
        IF NEW.data_aquisicao IS NOT NULL AND NEW.data_aquisicao > CURDATE() THEN
            SIGNAL SQLSTATE '45400' SET MESSAGE_TEXT = 'Data de aquisição no futuro.';
        END IF;
        IF NEW.status = 'em_manutencao' THEN
            SIGNAL SQLSTATE '45422'
                SET MESSAGE_TEXT = 'O status "em manutenção" só é definido por uma manutenção em andamento.';
        END IF;
    END IF;

    CALL sp_garantir_categoria(NEW.categoria);
    SET NEW.id_categoria = (SELECT id_categoria FROM categoria WHERE nome = NEW.categoria);

    IF fn_nome_setor(NEW.localizacao) IS NOT NULL THEN
        CALL sp_garantir_setor(fn_nome_setor(NEW.localizacao));
        SET NEW.id_setor = (SELECT id_setor FROM setor WHERE nome = fn_nome_setor(NEW.localizacao));
    END IF;
END $$


-- ANTES DE ATUALIZAR o bem (regras dos métodos da classe Equipamento):
--   * localizacao: bem em movimentação ou inativo não muda de lugar (use as
--     procedures de movimentação); mudou o texto -> acerta id_setor;
--   * status: 'em_manutencao' só com manutenção aberta; sair de 'em_manutencao'
--     ou ficar 'inativo' exige que não haja manutenção, movimentação ou chamado ativo;
--     bem inutilizável não é reativado;
--   * estado de conservação: melhora de 2+ níveis exige manutenção concluída;
--     'inutilizavel' sem chamado ativo baixa o bem (status 'inativo') automaticamente.

DROP TRIGGER IF EXISTS trg_equipamento_before_update $$

CREATE TRIGGER trg_equipamento_before_update
BEFORE UPDATE ON equipamento
FOR EACH ROW
BEGIN
    SET NEW.nome        = REGEXP_REPLACE(TRIM(NEW.nome), '[[:space:]]+', ' ');
    SET NEW.localizacao = NULLIF(TRIM(NEW.localizacao), '');
    SET NEW.categoria   = COALESCE(NULLIF(TRIM(NEW.categoria), ''), 'Outro');

    IF CHAR_LENGTH(NEW.nome) < 2 THEN
        SIGNAL SQLSTATE '45400' SET MESSAGE_TEXT = 'Nome do equipamento muito curto.';
    END IF;

    -- --- localização -------------------------------------------------
    IF NOT (OLD.localizacao <=> NEW.localizacao) THEN
        IF OLD.status = 'inativo' THEN
            SIGNAL SQLSTATE '45422'
                SET MESSAGE_TEXT = 'Equipamento inativo (baixado) não tem a localização alterada.';
        END IF;
        IF COALESCE(@edufix_movimentando, 0) = 0 AND fn_equipamento_em_movimentacao(OLD.id_equipamento) = 1 THEN
            SIGNAL SQLSTATE '45409'
                SET MESSAGE_TEXT = 'Equipamento em movimentação: conclua ou cancele a movimentação antes.';
        END IF;
    END IF;
    IF NOT (OLD.localizacao <=> NEW.localizacao) OR NEW.id_setor IS NULL THEN
        IF fn_nome_setor(NEW.localizacao) IS NULL THEN
            SET NEW.id_setor = NULL;
        ELSE
            CALL sp_garantir_setor(fn_nome_setor(NEW.localizacao));
            SET NEW.id_setor = (SELECT id_setor FROM setor WHERE nome = fn_nome_setor(NEW.localizacao));
        END IF;
    END IF;

    -- --- categoria ---------------------------------------------------
    IF NOT (OLD.categoria <=> NEW.categoria) OR NEW.id_categoria IS NULL THEN
        CALL sp_garantir_categoria(NEW.categoria);
        SET NEW.id_categoria = (SELECT id_categoria FROM categoria WHERE nome = NEW.categoria);
    END IF;

    -- --- estado de conservação --------------------------------------
    IF OLD.estado_conservacao <> NEW.estado_conservacao THEN
        IF fn_pode_melhorar_conservacao(OLD.id_equipamento, NEW.estado_conservacao) = 0 THEN
            SIGNAL SQLSTATE '45422'
                SET MESSAGE_TEXT = 'Melhora de 2 ou mais níveis exige uma manutenção concluída desde a última avaliação.';
        END IF;
    END IF;
    IF NEW.estado_conservacao = 'inutilizavel'
       AND OLD.status <> 'inativo'
       AND NEW.status IN ('disponivel', 'em_uso')
       AND fn_chamados_ativos_equipamento(OLD.id_equipamento) = 0
       AND fn_manutencoes_em_andamento(OLD.id_equipamento) = 0 THEN
        SET NEW.status = 'inativo';
    END IF;

    -- --- status ------------------------------------------------------
    IF NEW.status = 'em_manutencao' AND OLD.status <> 'em_manutencao'
       AND fn_manutencoes_em_andamento(OLD.id_equipamento) = 0 THEN
        SIGNAL SQLSTATE '45422'
            SET MESSAGE_TEXT = 'O status "em manutenção" só é definido por uma manutenção em andamento.';
    END IF;
    IF OLD.status = 'em_manutencao' AND NEW.status NOT IN ('em_manutencao', 'inativo')
       AND fn_manutencoes_em_andamento(OLD.id_equipamento) > 0 THEN
        SIGNAL SQLSTATE '45409'
            SET MESSAGE_TEXT = 'Há manutenção em andamento: conclua-a antes de mudar o status do equipamento.';
    END IF;
    IF NEW.status = 'inativo' AND OLD.status <> 'inativo' THEN
        IF fn_chamados_ativos_equipamento(OLD.id_equipamento) > 0 THEN
            SIGNAL SQLSTATE '45409'
                SET MESSAGE_TEXT = 'Equipamento com chamado em andamento não pode ser inativado.';
        END IF;
        IF fn_manutencoes_em_andamento(OLD.id_equipamento) > 0
           OR fn_equipamento_em_movimentacao(OLD.id_equipamento) = 1 THEN
            SIGNAL SQLSTATE '45409'
                SET MESSAGE_TEXT = 'Conclua a manutenção/movimentação antes de inativar o equipamento.';
        END IF;
    END IF;
    IF OLD.status = 'inativo' AND NEW.status <> 'inativo' AND NEW.estado_conservacao = 'inutilizavel' THEN
        SIGNAL SQLSTATE '45422'
            SET MESSAGE_TEXT = 'Equipamento inutilizável: reavalie a conservação antes de reativar.';
    END IF;
END $$


-- AUDITORIA 1: registra no log todo equipamento cadastrado.
-- usuario_banco guarda o usuário da APLICAÇÃO quando a procedure o informa
-- (variável @edufix_usuario); fora delas, o usuário do MySQL.

DROP TRIGGER IF EXISTS trg_equipamento_auditoria_insert $$

CREATE TRIGGER trg_equipamento_auditoria_insert
AFTER INSERT ON equipamento
FOR EACH ROW
BEGIN
    INSERT INTO log_patrimonio
        (id_equipamento, nome_equipamento, acao, valor_anterior, valor_novo, usuario_banco)
    VALUES
        (NEW.id_equipamento, NEW.nome, 'CADASTRO', NULL, NEW.localizacao,
         COALESCE(@edufix_usuario, CURRENT_USER()));
END $$


-- AUDITORIA 2: troca de sala (transferência), de status e de estado de conservação
-- geram uma linha de log cada. O operador <=> compara corretamente com NULL.

DROP TRIGGER IF EXISTS trg_equipamento_auditoria_update $$

CREATE TRIGGER trg_equipamento_auditoria_update
AFTER UPDATE ON equipamento
FOR EACH ROW
BEGIN
    IF NOT (OLD.localizacao <=> NEW.localizacao) THEN
        INSERT INTO log_patrimonio
            (id_equipamento, nome_equipamento, acao, valor_anterior, valor_novo, usuario_banco)
        VALUES
            (NEW.id_equipamento, NEW.nome, 'TRANSFERENCIA', OLD.localizacao, NEW.localizacao,
             COALESCE(@edufix_usuario, CURRENT_USER()));
    END IF;

    IF OLD.status <> NEW.status THEN
        INSERT INTO log_patrimonio
            (id_equipamento, nome_equipamento, acao, valor_anterior, valor_novo, usuario_banco)
        VALUES
            (NEW.id_equipamento, NEW.nome, 'MUDANCA_STATUS', OLD.status, NEW.status,
             COALESCE(@edufix_usuario, CURRENT_USER()));
    END IF;

    IF OLD.estado_conservacao <> NEW.estado_conservacao THEN
        INSERT INTO log_patrimonio
            (id_equipamento, nome_equipamento, acao, valor_anterior, valor_novo, usuario_banco)
        VALUES
            (NEW.id_equipamento, NEW.nome, 'MUDANCA_CONSERVACAO',
             OLD.estado_conservacao, NEW.estado_conservacao,
             COALESCE(@edufix_usuario, CURRENT_USER()));
    END IF;
END $$


-- VALIDAÇÃO 1: impede excluir equipamento que ainda está vinculado a chamado em
-- andamento ou que tem manutenção registrada. Erro 45409.

DROP TRIGGER IF EXISTS trg_equipamento_bloqueia_exclusao $$

CREATE TRIGGER trg_equipamento_bloqueia_exclusao
BEFORE DELETE ON equipamento
FOR EACH ROW
BEGIN
    IF fn_chamados_ativos_equipamento(OLD.id_equipamento) > 0 THEN
        SIGNAL SQLSTATE '45409'
            SET MESSAGE_TEXT = 'Equipamento com chamado em andamento não pode ser excluído.';
    END IF;
    IF EXISTS (SELECT 1
               FROM manutencao
               WHERE id_equipamento = OLD.id_equipamento) THEN
        SIGNAL SQLSTATE '45409'
            SET MESSAGE_TEXT = 'Equipamento com manutenções registradas não pode ser excluído. Marque-o como inativo.';
    END IF;
END $$


-- AUDITORIA 3: guarda no log a exclusão do equipamento (o log permanece).

DROP TRIGGER IF EXISTS trg_equipamento_auditoria_delete $$

CREATE TRIGGER trg_equipamento_auditoria_delete
AFTER DELETE ON equipamento
FOR EACH ROW
BEGIN
    INSERT INTO log_patrimonio
        (id_equipamento, nome_equipamento, acao, valor_anterior, valor_novo, usuario_banco)
    VALUES
        (OLD.id_equipamento, OLD.nome, 'EXCLUSAO', OLD.status, NULL,
         COALESCE(@edufix_usuario, CURRENT_USER()));
END $$


-- ============================================================
--  MOVIMENTAÇÃO DE EQUIPAMENTO (método registrarMovimentacao)
-- ============================================================

-- Ao abrir uma movimentação: quem move precisa ser admin com permissão de
-- patrimônio; bem inativo ou em manutenção não se move; origem é preenchida
-- sozinha com o setor atual e o destino precisa ser outro setor.

DROP TRIGGER IF EXISTS trg_movimentacao_valida_insert $$

CREATE TRIGGER trg_movimentacao_valida_insert
BEFORE INSERT ON movimentacao_equipamento
FOR EACH ROW
BEGIN
    DECLARE v_status VARCHAR(20);
    DECLARE v_setor  INT;

    IF fn_admin_tem_permissao(NEW.id_usuario, 'gerenciar_patrimonio') = 0 THEN
        SIGNAL SQLSTATE '45403'
            SET MESSAGE_TEXT = 'Apenas administradores com permissão de patrimônio movimentam bens.';
    END IF;

    SELECT status, id_setor INTO v_status, v_setor
    FROM equipamento
    WHERE id_equipamento = NEW.id_equipamento;

    IF v_status IN ('inativo', 'em_manutencao') THEN
        SIGNAL SQLSTATE '45422'
            SET MESSAGE_TEXT = 'Bem inativo ou em manutenção não pode ser movimentado.';
    END IF;

    IF NEW.id_setor_origem IS NULL THEN
        SET NEW.id_setor_origem = v_setor;
    END IF;
    IF NEW.id_setor_origem <=> NEW.id_setor_destino THEN
        SIGNAL SQLSTATE '45422'
            SET MESSAGE_TEXT = 'O destino é o próprio setor atual do bem.';
    END IF;
    SET NEW.situacao = 'em_transito';
    SET NEW.data_conclusao = NULL;
END $$


-- Movimentação já concluída/cancelada não muda mais.

DROP TRIGGER IF EXISTS trg_movimentacao_valida_update $$

CREATE TRIGGER trg_movimentacao_valida_update
BEFORE UPDATE ON movimentacao_equipamento
FOR EACH ROW
BEGIN
    IF OLD.situacao <> 'em_transito' THEN
        SIGNAL SQLSTATE '45409'
            SET MESSAGE_TEXT = 'Movimentação já encerrada não pode ser alterada.';
    END IF;
    IF NEW.situacao <> 'em_transito' AND NEW.data_conclusao IS NULL THEN
        SET NEW.data_conclusao = NOW();
    END IF;
END $$


-- ============================================================
--  MANUTENÇÃO (classe Manutencao: ligada ao equipamento PELO CHAMADO)
-- ============================================================

-- ANTES DE INSERIR a manutenção (método iniciarAtendimento):
--   * chamado em andamento (chamado encerrado precisa ser reaberto);
--   * o equipamento da manutenção é o equipamento DO CHAMADO;
--   * equipamento ativo e fora de movimentação;
--   * só uma manutenção em andamento por equipamento.

DROP TRIGGER IF EXISTS trg_manutencao_valida_insert $$

CREATE TRIGGER trg_manutencao_valida_insert
BEFORE INSERT ON manutencao
FOR EACH ROW
BEGIN
    DECLARE v_status_chamado VARCHAR(20);
    DECLARE v_equip_chamado  INT;

    IF COALESCE(@edufix_importacao, 0) = 0 THEN
        SELECT status, id_equipamento INTO v_status_chamado, v_equip_chamado
        FROM chamado
        WHERE id_chamado = NEW.id_chamado;

        IF v_status_chamado IS NULL THEN
            SIGNAL SQLSTATE '45404' SET MESSAGE_TEXT = 'Chamado não encontrado.';
        END IF;
        IF v_status_chamado IN ('concluido', 'cancelado') THEN
            SIGNAL SQLSTATE '45422'
                SET MESSAGE_TEXT = 'Chamado encerrado não recebe nova manutenção. Reabra o chamado.';
        END IF;
        IF v_equip_chamado IS NULL OR v_equip_chamado <> NEW.id_equipamento THEN
            SIGNAL SQLSTATE '45422'
                SET MESSAGE_TEXT = 'A manutenção deve ser do mesmo equipamento do chamado.';
        END IF;
        IF fn_equipamento_inativo(NEW.id_equipamento) = 1 THEN
            SIGNAL SQLSTATE '45422' SET MESSAGE_TEXT = 'Equipamento inativo não recebe manutenção.';
        END IF;
        IF NEW.data_fim IS NULL THEN
            IF fn_equipamento_em_movimentacao(NEW.id_equipamento) = 1 THEN
                SIGNAL SQLSTATE '45409'
                    SET MESSAGE_TEXT = 'Equipamento em movimentação: conclua a movimentação antes do reparo.';
            END IF;
            IF fn_manutencoes_em_andamento(NEW.id_equipamento) > 0 THEN
                SIGNAL SQLSTATE '45409'
                    SET MESSAGE_TEXT = 'Já existe uma manutenção em andamento para este equipamento.';
            END IF;
        END IF;
    END IF;
    IF NEW.tecnico_responsavel IS NOT NULL THEN
        SET NEW.tecnico_responsavel = REGEXP_REPLACE(TRIM(NEW.tecnico_responsavel), '[[:space:]]+', ' ');
    END IF;
END $$


-- ANTES DE ATUALIZAR a manutenção (concluirAtendimento):
--   * concluir (preencher data_fim) exige a descrição do serviço realizado;
--   * reabrir (limpar data_fim) exige chamado em andamento e nenhuma outra manutenção aberta;
--   * chamado/equipamento continuam coerentes entre si.

DROP TRIGGER IF EXISTS trg_manutencao_valida_update $$

CREATE TRIGGER trg_manutencao_valida_update
BEFORE UPDATE ON manutencao
FOR EACH ROW
BEGIN
    DECLARE v_status_chamado VARCHAR(20);
    DECLARE v_equip_chamado  INT;

    IF NOT (OLD.id_chamado <=> NEW.id_chamado) OR NOT (OLD.id_equipamento <=> NEW.id_equipamento) THEN
        SELECT id_equipamento INTO v_equip_chamado
        FROM chamado
        WHERE id_chamado = NEW.id_chamado;

        IF v_equip_chamado IS NULL OR v_equip_chamado <> NEW.id_equipamento THEN
            SIGNAL SQLSTATE '45422'
                SET MESSAGE_TEXT = 'A manutenção deve ser do mesmo equipamento do chamado.';
        END IF;
    END IF;

    -- Concluir sem descrever (botão "Concluir" da tela): grava um texto padrão
    -- em vez de travar. Quem quiser exigir descrição usa sp_concluir_manutencao.
    IF OLD.data_fim IS NULL AND NEW.data_fim IS NOT NULL
       AND COALESCE(TRIM(NEW.descricao_servico), '') = '' THEN
        SET NEW.descricao_servico = 'Serviço concluído (sem descrição detalhada).';
    END IF;

    IF OLD.data_fim IS NOT NULL AND NEW.data_fim IS NULL THEN
        SELECT status INTO v_status_chamado
        FROM chamado
        WHERE id_chamado = NEW.id_chamado;

        IF v_status_chamado IN ('concluido', 'cancelado') THEN
            SIGNAL SQLSTATE '45422'
                SET MESSAGE_TEXT = 'Chamado encerrado: reabra o chamado antes de reabrir a manutenção.';
        END IF;
        IF fn_manutencoes_em_andamento(NEW.id_equipamento) > 0 THEN
            SIGNAL SQLSTATE '45409'
                SET MESSAGE_TEXT = 'Já existe uma manutenção em andamento para este equipamento.';
        END IF;
    END IF;
END $$


-- Mantém o status do equipamento coerente com as manutenções
-- (a regra em si está na procedure sp_sincronizar_equipamento).

DROP TRIGGER IF EXISTS trg_manutencao_after_insert $$

CREATE TRIGGER trg_manutencao_after_insert
AFTER INSERT ON manutencao
FOR EACH ROW
BEGIN
    CALL sp_sincronizar_equipamento(NEW.id_equipamento);
END $$


DROP TRIGGER IF EXISTS trg_manutencao_after_update $$

CREATE TRIGGER trg_manutencao_after_update
AFTER UPDATE ON manutencao
FOR EACH ROW
BEGIN
    CALL sp_sincronizar_equipamento(NEW.id_equipamento);
    IF OLD.id_equipamento <> NEW.id_equipamento THEN
        CALL sp_sincronizar_equipamento(OLD.id_equipamento);
    END IF;
END $$


DROP TRIGGER IF EXISTS trg_manutencao_after_delete $$

CREATE TRIGGER trg_manutencao_after_delete
AFTER DELETE ON manutencao
FOR EACH ROW
BEGIN
    CALL sp_sincronizar_equipamento(OLD.id_equipamento);
END $$

DELIMITER ;
