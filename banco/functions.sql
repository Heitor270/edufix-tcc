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
 
 
-- ============================================================
--  FUNCTIONS DE APOIO ÀS TRIGGERS E VIEWS (trabalho de Banco II)
-- ============================================================
 
-- Conta os chamados de um equipamento que ainda estão em andamento
-- (aberto, em análise ou em execução).
-- Uso: trigger trg_equipamento_bloqueia_exclusao e views de patrimônio.
 
DROP FUNCTION IF EXISTS fn_chamados_ativos_equipamento $$
 
CREATE FUNCTION fn_chamados_ativos_equipamento(p_id_equipamento INT)
RETURNS INT
DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_total INT;
 
    SELECT COUNT(*)
    INTO v_total
    FROM chamado
    WHERE id_equipamento = p_id_equipamento
      AND status IN ('aberto', 'em_analise', 'em_execucao');
 
    RETURN v_total;
END $$
 
 
-- Informa se o equipamento está inativo (baixado do patrimônio).
-- Retorna 1 (sim) ou 0 (não, ou equipamento inexistente).
-- Uso: trigger trg_chamado_valida_equipamento e procedure sp_transferir_equipamento.
 
DROP FUNCTION IF EXISTS fn_equipamento_inativo $$
 
CREATE FUNCTION fn_equipamento_inativo(p_id_equipamento INT)
RETURNS TINYINT(1)
DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_total INT;
 
    SELECT COUNT(*)
    INTO v_total
    FROM equipamento
    WHERE id_equipamento = p_id_equipamento
      AND status = 'inativo';
 
    RETURN v_total > 0;
END $$
 
 
-- ============================================================
--  FUNCTIONS DA v3 (alinhadas às classes do diagrama UML)
-- ============================================================
 
-- Valida um CPF pelos dois dígitos verificadores (mesmo algoritmo da classe
-- Usuario e do frontend). Aceita com ou sem máscara. Retorna 1 (válido) ou 0.
-- Uso: trigger trg_usuario_normaliza_insert/update.
 
DROP FUNCTION IF EXISTS fn_validar_cpf $$
 
CREATE FUNCTION fn_validar_cpf(p_cpf VARCHAR(20))
RETURNS TINYINT(1)
DETERMINISTIC
NO SQL
BEGIN
    DECLARE v_i      INT DEFAULT 1;
    DECLARE v_c      CHAR(1);
    DECLARE v_d      INT;
    DECLARE v_qtd    INT DEFAULT 0;   -- quantos dígitos já foram lidos
    DECLARE v_primeiro INT DEFAULT 0; -- 1º dígito (para detectar 111.111.111-11 etc.)
    DECLARE v_iguais INT DEFAULT 1;   -- 1 = todos os dígitos são iguais
    DECLARE v_soma1  INT DEFAULT 0;   -- soma ponderada dos 9 primeiros (pesos 10..2)
    DECLARE v_soma2  INT DEFAULT 0;   -- soma ponderada dos 10 primeiros (pesos 11..2)
    DECLARE v_dig10  INT DEFAULT 0;   -- 1º dígito verificador informado
    DECLARE v_dig11  INT DEFAULT 0;   -- 2º dígito verificador informado
 
    IF p_cpf IS NULL THEN
        RETURN 0;
    END IF;
 
    -- Lê o texto caractere a caractere e usa só os dígitos (aceita com ou sem máscara).
    -- Não usa REGEXP_REPLACE de propósito: no MySQL 8 ele se comporta de forma
    -- inesperada dentro de funções e fazia CPFs válidos serem recusados.
    WHILE v_i <= CHAR_LENGTH(p_cpf) DO
        SET v_c = SUBSTRING(p_cpf, v_i, 1);
        IF v_c BETWEEN '0' AND '9' THEN
            SET v_d   = ASCII(v_c) - 48;
            SET v_qtd = v_qtd + 1;
            IF v_qtd = 1 THEN
                SET v_primeiro = v_d;
            ELSEIF v_d <> v_primeiro THEN
                SET v_iguais = 0;
            END IF;
            IF v_qtd <= 9 THEN
                SET v_soma1 = v_soma1 + v_d * (11 - v_qtd);
            END IF;
            IF v_qtd <= 10 THEN
                SET v_soma2 = v_soma2 + v_d * (12 - v_qtd);
            END IF;
            IF v_qtd = 10 THEN
                SET v_dig10 = v_d;
            ELSEIF v_qtd = 11 THEN
                SET v_dig11 = v_d;
            END IF;
        ELSEIF v_c NOT IN ('.', '-', ' ') THEN
            RETURN 0;                 -- letra ou símbolo estranho
        END IF;
        SET v_i = v_i + 1;
    END WHILE;
 
    IF v_qtd <> 11 OR v_iguais = 1 THEN
        RETURN 0;
    END IF;
 
    IF ((v_soma1 * 10) MOD 11) MOD 10 <> v_dig10 THEN
        RETURN 0;
    END IF;
    IF ((v_soma2 * 10) MOD 11) MOD 10 <> v_dig11 THEN
        RETURN 0;
    END IF;
 
    RETURN 1;
END $$
 
 
-- Valida o formato do e-mail (mesma regra do backend e do frontend).
 
DROP FUNCTION IF EXISTS fn_validar_email $$
 
CREATE FUNCTION fn_validar_email(p_email VARCHAR(255))
RETURNS TINYINT(1)
DETERMINISTIC
NO SQL
BEGIN
    IF p_email IS NULL OR CHAR_LENGTH(p_email) > 100 OR p_email LIKE '%..%' THEN
        RETURN 0;
    END IF;
    RETURN p_email REGEXP '^[A-Za-z0-9][A-Za-z0-9._%+-]*@([A-Za-z0-9-]+[.])+[A-Za-z]{2,}$';
END $$
 
 
-- Prazo (SLA) em horas de cada prioridade: crítica 4h, alta 24h, média 72h, baixa 168h.
-- Mesma tabela da classe Chamado (PRAZO_SLA_HORAS).
 
DROP FUNCTION IF EXISTS fn_sla_horas $$
 
CREATE FUNCTION fn_sla_horas(p_prioridade VARCHAR(10))
RETURNS INT
DETERMINISTIC
NO SQL
BEGIN
    RETURN CASE p_prioridade
               WHEN 'critica' THEN 4
               WHEN 'alta'    THEN 24
               WHEN 'media'   THEN 72
               WHEN 'baixa'   THEN 168
               ELSE 72
           END;
END $$
 
 
-- Horas decorridas do chamado: da abertura até o fechamento (ou até agora, se ainda aberto).
 
DROP FUNCTION IF EXISTS fn_horas_chamado $$
 
CREATE FUNCTION fn_horas_chamado(p_id_chamado INT)
RETURNS DECIMAL(10, 2)
NOT DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_horas DECIMAL(10, 2);
 
    SELECT ROUND(TIMESTAMPDIFF(SECOND, data_abertura, COALESCE(data_fechamento, NOW())) / 3600, 2)
    INTO v_horas
    FROM chamado
    WHERE id_chamado = p_id_chamado;
 
    RETURN v_horas;
END $$
 
 
-- Retorna 1 se o chamado passou do prazo de SLA da sua prioridade.
-- Chamado cancelado não entra na conta (retorna 0).
 
DROP FUNCTION IF EXISTS fn_chamado_sla_estourado $$
 
CREATE FUNCTION fn_chamado_sla_estourado(p_id_chamado INT)
RETURNS TINYINT(1)
NOT DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_prioridade VARCHAR(10);
    DECLARE v_status     VARCHAR(20);
 
    SELECT prioridade, status INTO v_prioridade, v_status
    FROM chamado
    WHERE id_chamado = p_id_chamado;
 
    IF v_status IS NULL OR v_status = 'cancelado' THEN
        RETURN 0;
    END IF;
 
    RETURN fn_horas_chamado(p_id_chamado) > fn_sla_horas(v_prioridade);
END $$
 
 
-- Regra de transição de status do chamado (mesma tabela TRANSICOES_VALIDAS da classe
-- HistoricoStatusChamado). Retorna 1 se a mudança de p_de para p_para é permitida.
--   aberto      -> em_analise, em_execucao, cancelado
--   em_analise  -> em_execucao, cancelado, aberto
--   em_execucao -> concluido, cancelado, em_analise
--   concluido / cancelado -> aberto (reabertura)
 
DROP FUNCTION IF EXISTS fn_transicao_status_valida $$
 
CREATE FUNCTION fn_transicao_status_valida(p_de VARCHAR(20), p_para VARCHAR(20))
RETURNS TINYINT(1)
DETERMINISTIC
NO SQL
BEGIN
    RETURN CASE p_de
               WHEN 'aberto'      THEN p_para IN ('em_analise', 'em_execucao', 'concluido', 'cancelado')
               WHEN 'em_analise'  THEN p_para IN ('em_execucao', 'concluido', 'cancelado', 'aberto')
               WHEN 'em_execucao' THEN p_para IN ('concluido', 'cancelado', 'em_analise')
               WHEN 'concluido'   THEN p_para = 'aberto'
               WHEN 'cancelado'   THEN p_para = 'aberto'
               ELSE 0
           END;
END $$
 
 
-- Posição do estado de conservação, do pior (0) ao melhor (4).
-- Uso: comparar se um estado "melhorou" ou "piorou".
 
DROP FUNCTION IF EXISTS fn_nivel_conservacao $$
 
CREATE FUNCTION fn_nivel_conservacao(p_estado VARCHAR(20))
RETURNS INT
DETERMINISTIC
NO SQL
BEGIN
    RETURN FIELD(p_estado, 'inutilizavel', 'ruim', 'regular', 'bom', 'otimo') - 1;
END $$
 
 
-- Sugere a prioridade de um chamado (método classificarPrioridade da classe Chamado).
-- Soma 3 sinais:
--   1) palavras da descrição:  risco (fogo, fumaça, curto...) = 4 | parada (não liga,
--      quebrado...) = 2 | degradação (lento, ruído...) = 1
--   2) conservação do bem: ruim = +1, inutilizável = +2
--   3) reincidência: 2-3 chamados do mesmo bem nos últimos 30 dias = +1, 4 ou mais = +2
-- Pontos: 4+ crítica | 2-3 alta | 1 média | 0 baixa.
 
DROP FUNCTION IF EXISTS fn_classificar_prioridade $$
 
CREATE FUNCTION fn_classificar_prioridade(p_descricao TEXT, p_id_equipamento INT)
RETURNS VARCHAR(10)
NOT DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_pontos   INT DEFAULT 0;
    DECLARE v_estado   VARCHAR(20);
    DECLARE v_recentes INT DEFAULT 0;
 
    IF p_descricao LIKE '%fogo%' OR p_descricao LIKE '%fumaca%' OR p_descricao LIKE '%faisca%'
       OR p_descricao LIKE '%curto circuito%' OR p_descricao LIKE '%curto-circuito%'
       OR p_descricao LIKE '%choque%' OR p_descricao LIKE '%cheiro de queimado%'
       OR p_descricao LIKE '%incendio%' OR p_descricao LIKE '%vazamento de gas%' THEN
        SET v_pontos = 4;
    ELSEIF p_descricao LIKE '%nao liga%' OR p_descricao LIKE '%parou%' OR p_descricao LIKE '%quebrad%'
       OR p_descricao LIKE '%travad%' OR p_descricao LIKE '%sem energia%' OR p_descricao LIKE '%sem agua%'
       OR p_descricao LIKE '%nao funciona%' OR p_descricao LIKE '%queimou%'
       OR p_descricao LIKE '%estourou%' OR p_descricao LIKE '%inoperante%' THEN
        SET v_pontos = 2;
    ELSEIF p_descricao LIKE '%lento%' OR p_descricao LIKE '%ruido%' OR p_descricao LIKE '%falha%'
       OR p_descricao LIKE '%intermitente%' OR p_descricao LIKE '%piscando%'
       OR p_descricao LIKE '%vazando%' OR p_descricao LIKE '%goteira%'
       OR p_descricao LIKE '%emperrad%' OR p_descricao LIKE '%barulho%' THEN
        SET v_pontos = 1;
    END IF;
 
    IF p_id_equipamento IS NOT NULL THEN
        SELECT estado_conservacao INTO v_estado
        FROM equipamento
        WHERE id_equipamento = p_id_equipamento;
 
        IF v_estado = 'ruim' THEN
            SET v_pontos = v_pontos + 1;
        ELSEIF v_estado = 'inutilizavel' THEN
            SET v_pontos = v_pontos + 2;
        END IF;
 
        SELECT COUNT(*) INTO v_recentes
        FROM chamado
        WHERE id_equipamento = p_id_equipamento
          AND data_abertura >= (NOW() - INTERVAL 30 DAY);
 
        IF v_recentes >= 4 THEN
            SET v_pontos = v_pontos + 2;
        ELSEIF v_recentes >= 2 THEN
            SET v_pontos = v_pontos + 1;
        END IF;
    END IF;
 
    RETURN CASE WHEN v_pontos >= 4 THEN 'critica'
                WHEN v_pontos >= 2 THEN 'alta'
                WHEN v_pontos >= 1 THEN 'media'
                ELSE 'baixa'
           END;
END $$
 
 
-- Nome do setor a partir da localização do bem: só o que vem antes de " - ".
-- Ex.: 'Secretaria - sala 2' -> 'Secretaria'. Localização vazia -> NULL.
-- Uso: o trigger do equipamento liga o bem à tabela setor com esse nome.
 
DROP FUNCTION IF EXISTS fn_nome_setor $$
 
CREATE FUNCTION fn_nome_setor(p_localizacao VARCHAR(100))
RETURNS VARCHAR(100)
DETERMINISTIC
NO SQL
BEGIN
    RETURN NULLIF(TRIM(SUBSTRING_INDEX(COALESCE(p_localizacao, ''), ' - ', 1)), '');
END $$
 
 
-- Retorna 1 se o bem está "em trânsito" (movimentação iniciada e ainda não concluída).
-- Corresponde à propriedade em_movimentacao da classe Equipamento.
 
DROP FUNCTION IF EXISTS fn_equipamento_em_movimentacao $$
 
CREATE FUNCTION fn_equipamento_em_movimentacao(p_id_equipamento INT)
RETURNS TINYINT(1)
NOT DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_total INT;
 
    SELECT COUNT(*) INTO v_total
    FROM movimentacao_equipamento
    WHERE id_equipamento = p_id_equipamento
      AND situacao = 'em_transito';
 
    RETURN v_total > 0;
END $$
 
 
-- Conta os bens de um setor (método contarBens da classe Setor).
-- p_status NULL = todos os status.
 
DROP FUNCTION IF EXISTS fn_total_bens_setor $$
 
CREATE FUNCTION fn_total_bens_setor(p_id_setor INT, p_status VARCHAR(20))
RETURNS INT
NOT DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_total INT;
 
    SELECT COUNT(*) INTO v_total
    FROM equipamento
    WHERE id_setor = p_id_setor
      AND (p_status IS NULL OR status = p_status);
 
    RETURN v_total;
END $$
 
 
-- Idade do bem em anos (a partir da data de aquisição).
 
DROP FUNCTION IF EXISTS fn_idade_equipamento_anos $$
 
CREATE FUNCTION fn_idade_equipamento_anos(p_id_equipamento INT)
RETURNS DECIMAL(5, 1)
NOT DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_data DATE;
 
    SELECT data_aquisicao INTO v_data
    FROM equipamento
    WHERE id_equipamento = p_id_equipamento;
 
    IF v_data IS NULL THEN
        RETURN NULL;
    END IF;
 
    RETURN ROUND(DATEDIFF(CURDATE(), v_data) / 365.25, 1);
END $$
 
 
-- Conta as manutenções em andamento de um CHAMADO (sem data_fim).
-- Uso: um chamado não pode ser concluído/cancelado com manutenção aberta.
 
DROP FUNCTION IF EXISTS fn_manutencoes_em_andamento_chamado $$
 
CREATE FUNCTION fn_manutencoes_em_andamento_chamado(p_id_chamado INT)
RETURNS INT
NOT DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_total INT;
 
    SELECT COUNT(*) INTO v_total
    FROM manutencao
    WHERE id_chamado = p_id_chamado
      AND data_fim IS NULL;
 
    RETURN v_total;
END $$
 
 
-- Custo de UMA manutenção (método calcularCustoTotal da classe Manutencao):
-- custo de peças/serviços + (dias trabalhados x 8h x taxa por hora de mão de obra).
-- Só calcula; não altera nada. Manutenção em andamento conta até hoje.
 
DROP FUNCTION IF EXISTS fn_custo_manutencao_total $$
 
CREATE FUNCTION fn_custo_manutencao_total(p_id_manutencao INT, p_taxa_hora DECIMAL(10, 2))
RETURNS DECIMAL(10, 2)
NOT DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_custo  DECIMAL(10, 2);
    DECLARE v_inicio DATE;
    DECLARE v_fim    DATE;
 
    SELECT custo, data_inicio, data_fim INTO v_custo, v_inicio, v_fim
    FROM manutencao
    WHERE id_manutencao = p_id_manutencao;
 
    IF v_custo IS NULL THEN
        RETURN NULL;
    END IF;
 
    RETURN ROUND(v_custo + (DATEDIFF(COALESCE(v_fim, CURDATE()), v_inicio) + 1) * 8
                           * COALESCE(p_taxa_hora, 0), 2);
END $$
 
 
-- Retorna 1 se a melhora do estado de conservação é permitida: melhora de 1 nível
-- sempre pode; melhora de 2 ou mais níveis só se houve manutenção CONCLUÍDA depois da
-- última avaliação do bem (regra do método atualizarEstadoConservacao).
 
DROP FUNCTION IF EXISTS fn_pode_melhorar_conservacao $$
 
CREATE FUNCTION fn_pode_melhorar_conservacao(p_id_equipamento INT, p_estado_novo VARCHAR(20))
RETURNS TINYINT(1)
NOT DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_atual    VARCHAR(20);
    DECLARE v_ultima   DATETIME;
    DECLARE v_reparos  INT;
 
    SELECT estado_conservacao INTO v_atual
    FROM equipamento
    WHERE id_equipamento = p_id_equipamento;
 
    IF fn_nivel_conservacao(p_estado_novo) - fn_nivel_conservacao(v_atual) < 2 THEN
        RETURN 1;
    END IF;
 
    SELECT MAX(data_hora) INTO v_ultima
    FROM log_patrimonio
    WHERE id_equipamento = p_id_equipamento
      AND acao IN ('CADASTRO', 'MUDANCA_CONSERVACAO');
 
    IF v_ultima IS NULL THEN        -- bem antigo, sem histórico de auditoria
        RETURN 1;
    END IF;
 
    SELECT COUNT(*) INTO v_reparos
    FROM manutencao
    WHERE id_equipamento = p_id_equipamento
      AND data_fim IS NOT NULL
      AND data_fim >= DATE(v_ultima);
 
    RETURN v_reparos > 0;
END $$
 
 
-- Permissões do administrador (método possui_permissao da classe Admin).
-- p_permissao: gerenciar_usuarios | gerenciar_chamados | gerenciar_patrimonio | emitir_relatorios
--   * a lista admin.permissoes pode conter a palavra "admin" (= todas) ou a permissão pedida;
--   * o NÍVEL garante o mínimo: 1 = chamados + patrimônio | 2 = + relatórios | 3 ou mais = + usuários.
-- Usuário inativo, inexistente ou que não é admin: sempre 0.
 
DROP FUNCTION IF EXISTS fn_admin_tem_permissao $$
 
CREATE FUNCTION fn_admin_tem_permissao(p_id_usuario INT, p_permissao VARCHAR(40))
RETURNS TINYINT(1)
NOT DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_nivel INT;
    DECLARE v_lista TEXT;
 
    SELECT a.nivel_acesso, LOWER(REPLACE(COALESCE(a.permissoes, ''), ' ', ''))
    INTO v_nivel, v_lista
    FROM admin a
    INNER JOIN usuario u ON u.id_usuario = a.id_admin
    WHERE a.id_admin = p_id_usuario
      AND u.ativo = TRUE
      AND u.tipo_usuario = 'admin';
 
    IF v_nivel IS NULL THEN
        RETURN 0;
    END IF;
 
    IF FIND_IN_SET('admin', v_lista) > 0 OR FIND_IN_SET(p_permissao, v_lista) > 0 THEN
        RETURN 1;
    END IF;
 
    RETURN CASE p_permissao
               WHEN 'gerenciar_chamados'   THEN 1
               WHEN 'gerenciar_patrimonio' THEN 1
               WHEN 'emitir_relatorios'    THEN v_nivel >= 2
               WHEN 'gerenciar_usuarios'   THEN v_nivel >= 3
               ELSE 0
           END;
END $$
 
DELIMITER ;