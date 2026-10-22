-- ============================================================
--  EduFix / inventario_escolar
--  Tópico 6 - Triggers (regras automáticas do banco)
-- ============================================================

USE inventario_escolar;

DELIMITER $$

-- Preenche (ou limpa) a data de fechamento do chamado sozinha:
--   concluido / cancelado -> data_fechamento = agora (se ainda estiver vazia)
--   qualquer outro status -> data_fechamento = NULL (chamado reaberto)

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
END $$


-- Padroniza os dados do usuário: e-mail em minúsculas e sem espaços nas
-- pontas; nome sem espaços sobrando. Evita "Ana@x.com" e "ana@x.com "
-- virarem cadastros diferentes.

DROP TRIGGER IF EXISTS trg_usuario_normaliza_insert $$

CREATE TRIGGER trg_usuario_normaliza_insert
BEFORE INSERT ON usuario
FOR EACH ROW
BEGIN
    SET NEW.nome = TRIM(NEW.nome);
    IF NEW.email IS NOT NULL THEN
        SET NEW.email = LOWER(TRIM(NEW.email));
    END IF;
END $$


DROP TRIGGER IF EXISTS trg_usuario_normaliza_update $$

CREATE TRIGGER trg_usuario_normaliza_update
BEFORE UPDATE ON usuario
FOR EACH ROW
BEGIN
    SET NEW.nome = TRIM(NEW.nome);
    IF NEW.email IS NOT NULL THEN
        SET NEW.email = LOWER(TRIM(NEW.email));
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
