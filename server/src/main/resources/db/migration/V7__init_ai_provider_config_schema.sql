-- V1.2 BYOK AI Provider 配置表：保存用户自定义供应商和脱敏配置状态。
-- 安全边界：API Key 不得明文保存；后续迁移会补充加密字段和指纹字段。
CREATE TABLE ai_provider_configs (
    id BIGINT NOT NULL AUTO_INCREMENT,
    user_id BIGINT NOT NULL,
    provider_name VARCHAR(128) NOT NULL,
    base_url VARCHAR(512) NOT NULL,
    model_name VARCHAR(128) NOT NULL,
    api_key_fingerprint VARCHAR(64) NULL,
    secure_storage_status VARCHAR(64) NOT NULL,
    enabled TINYINT NOT NULL DEFAULT 1,
    default_provider TINYINT NOT NULL DEFAULT 0,
    deleted TINYINT NOT NULL DEFAULT 0,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    deleted_at DATETIME NULL,
    PRIMARY KEY (id),
    KEY idx_ai_provider_configs_user_deleted (user_id, deleted),
    KEY idx_ai_provider_configs_user_default (user_id, default_provider, deleted),
    CONSTRAINT fk_ai_provider_configs_user
        FOREIGN KEY (user_id) REFERENCES users (id)
        ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
