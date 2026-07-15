-- V2.0 会员激活码表：保存一次性兑换码的哈希、状态和审计字段。
-- 安全边界：只保存 code_hash 和脱敏元数据，不保存明文激活码或后台操作员凭据。
CREATE TABLE membership_activation_codes (
    id BIGINT NOT NULL AUTO_INCREMENT,
    code_hash VARCHAR(64) NOT NULL,
    membership_level VARCHAR(32) NOT NULL,
    ocr_quota INT NOT NULL,
    ai_quota INT NOT NULL,
    export_quota INT NOT NULL,
    status VARCHAR(32) NOT NULL,
    expires_at DATETIME NULL,
    redeemed_by_user_id BIGINT NULL,
    redeemed_at DATETIME NULL,
    created_by_admin_user_id BIGINT NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    note VARCHAR(512) NULL,
    PRIMARY KEY (id),
    UNIQUE KEY uk_activation_codes_hash (code_hash),
    KEY idx_activation_codes_status_expires (status, expires_at),
    KEY idx_activation_codes_redeemed_user (redeemed_by_user_id),
    KEY idx_activation_codes_admin_created (created_by_admin_user_id, created_at),
    CONSTRAINT fk_activation_codes_redeemed_user
        FOREIGN KEY (redeemed_by_user_id) REFERENCES users (id)
        ON DELETE SET NULL,
    CONSTRAINT fk_activation_codes_admin_user
        FOREIGN KEY (created_by_admin_user_id) REFERENCES users (id)
        ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
