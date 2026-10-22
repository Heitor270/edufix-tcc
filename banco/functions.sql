USE inventario_escolar;
 
DELIMITER $$
 
-- Calcula o custo total de todas as manutenções de um equipamento.
-- Uso: cálculo automático e totalização.

DROP FUNCTION IF EXISTS fn_custo_total_manutencao $$
 
CREATE FUNCTION fn_custo_total_manutencao(p_id_equipamento INT)
RETURNS DECIMAL(10, 2)
DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_total DECIMAL(10, 2);
 
    SELECT COALESCE(SUM(custo), 0.00)
    INTO v_total
    FROM manutencao
    WHERE id_equipamento = p_id_equipamento;
 
    RETURN v_total;
END $$
 

-- Retorna a quantidade de chamados com status 'aberto' de um usuário.
-- Uso: retorno de indicador por usuário.

DROP FUNCTION IF EXISTS fn_total_chamados_abertos $$
 
CREATE FUNCTION fn_total_chamados_abertos(p_id_usuario INT)
RETURNS INT
DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_total INT;
 
    SELECT COUNT(*)
    INTO v_total
    FROM chamado
    WHERE id_usuario = p_id_usuario
      AND status = 'aberto';
 
    RETURN v_total;
END $$
 

-- Verifica se um equipamento está disponível para uso.
-- Retorna 'Disponível' ou 'Indisponível'.
-- Uso: validação de status antes de vincular a um chamado.

DROP FUNCTION IF EXISTS fn_verificar_disponibilidade $$
 
CREATE FUNCTION fn_verificar_disponibilidade(p_id_equipamento INT)
RETURNS VARCHAR(20)
DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_status VARCHAR(50);
 
    SELECT status
    INTO v_status
    FROM equipamento
    WHERE id_equipamento = p_id_equipamento;
 
    IF v_status = 'disponivel' THEN
        RETURN 'Disponível';
    ELSE
        RETURN 'Indisponível';
    END IF;
END $$
 

-- Calcula em dias o tempo de resolução de um chamado.
-- Se ainda aberto, calcula até a data atual.
-- Uso: cálculo automático de indicador de desempenho.

DROP FUNCTION IF EXISTS fn_tempo_resolucao_chamado $$
 
CREATE FUNCTION fn_tempo_resolucao_chamado(p_id_chamado INT)
RETURNS INT
DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_abertura  DATETIME;
    DECLARE v_fechamento DATETIME;
 
    SELECT data_abertura, data_fechamento
    INTO v_abertura, v_fechamento
    FROM chamado
    WHERE id_chamado = p_id_chamado;
 
    IF v_fechamento IS NULL THEN
        RETURN DATEDIFF(NOW(), v_abertura);
    END IF;
 
    RETURN DATEDIFF(v_fechamento, v_abertura);
END $$
 

-- Retorna o total de chamados vinculados a um equipamento.
-- Uso: indicador de histórico de problemas do equipamento.

DROP FUNCTION IF EXISTS fn_total_chamados_equipamento $$
 
CREATE FUNCTION fn_total_chamados_equipamento(p_id_equipamento INT)
RETURNS INT
DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_total INT;
 
    SELECT COUNT(*)
    INTO v_total
    FROM chamado
    WHERE id_equipamento = p_id_equipamento;
 
    RETURN v_total;
END $$


-- ============================================================
--  NOVAS FUNCTIONS (sprint: consultas, relatórios e perfis)
-- ============================================================

-- Informa se um usuário é administrador ATIVO.
-- Retorna 1 (sim) ou 0 (não).
-- Uso: controle de acesso da aplicação (tela de Usuários, relatório de
-- usuários e rotas /usuarios e /admin só funcionam para administrador).

DROP FUNCTION IF EXISTS fn_usuario_eh_admin $$

CREATE FUNCTION fn_usuario_eh_admin(p_id_usuario INT)
RETURNS TINYINT(1)
DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_total INT;

    SELECT COUNT(*)
    INTO v_total
    FROM usuario
    WHERE id_usuario  = p_id_usuario
      AND tipo_usuario = 'admin'
      AND ativo        = TRUE;

    RETURN v_total > 0;
END $$


-- Conta as manutenções de um equipamento que ainda estão em andamento
-- (ou seja, sem data de fim).
-- Uso: decidir se o equipamento deve ficar 'em_manutencao' ou 'disponivel'.

DROP FUNCTION IF EXISTS fn_manutencoes_em_andamento $$

CREATE FUNCTION fn_manutencoes_em_andamento(p_id_equipamento INT)
RETURNS INT
DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_total INT;

    SELECT COUNT(*)
    INTO v_total
    FROM manutencao
    WHERE id_equipamento = p_id_equipamento
      AND data_fim IS NULL;

    RETURN v_total;
END $$


-- Soma os registros que impedem a remoção de um usuário:
-- chamados abertos por ele + alterações de status feitas por ele.
-- Uso: regra de integridade antes de excluir (se > 0, só desativar).

DROP FUNCTION IF EXISTS fn_total_vinculos_usuario $$

CREATE FUNCTION fn_total_vinculos_usuario(p_id_usuario INT)
RETURNS INT
DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_chamados  INT;
    DECLARE v_historico INT;

    SELECT COUNT(*) INTO v_chamados
    FROM chamado
    WHERE id_usuario = p_id_usuario;

    SELECT COUNT(*) INTO v_historico
    FROM historico_status_chamado
    WHERE id_usuario = p_id_usuario;

    RETURN v_chamados + v_historico;
END $$


-- Calcula o custo total das manutenções ligadas a um chamado.
-- Uso: indicador de custo por chamado.

DROP FUNCTION IF EXISTS fn_custo_total_chamado $$

CREATE FUNCTION fn_custo_total_chamado(p_id_chamado INT)
RETURNS DECIMAL(10, 2)
DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_total DECIMAL(10, 2);

    SELECT COALESCE(SUM(custo), 0.00)
    INTO v_total
    FROM manutencao
    WHERE id_chamado = p_id_chamado;

    RETURN v_total;
END $$

DELIMITER ;
