-- V2.0 管理账号、会员和额度统计基础表。
-- 安全边界：管理身份和用户额度必须由后端鉴权；迁移不包含任何真实管理员密码或生产额度数据。
CREATE TABLE admin_accounts (
    id BIGINT NOT NULL AUTO_INCREMENT,
    user_id BIGINT NOT NULL,
    role VARCHAR(64) NOT NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    UNIQUE KEY uk_admin_accounts_user (user_id),
    KEY idx_admin_accounts_role (role),
    CONSTRAINT fk_admin_accounts_user
        FOREIGN KEY (user_id) REFERENCES users (id)
        ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE user_memberships (
    user_id BIGINT NOT NULL,
    membership_level VARCHAR(32) NOT NULL,
    ocr_quota INT NOT NULL,
    ai_quota INT NOT NULL,
    export_quota INT NOT NULL,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (user_id),
    CONSTRAINT fk_user_memberships_user
        FOREIGN KEY (user_id) REFERENCES users (id)
        ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE usage_counters (
    id BIGINT NOT NULL AUTO_INCREMENT,
    user_id BIGINT NOT NULL,
    resource_type VARCHAR(32) NOT NULL,
    used_count INT NOT NULL DEFAULT 0,
    period_key VARCHAR(16) NOT NULL,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    UNIQUE KEY uk_usage_user_resource_period (user_id, resource_type, period_key),
    KEY idx_usage_resource_period (resource_type, period_key),
    CONSTRAINT fk_usage_counters_user
        FOREIGN KEY (user_id) REFERENCES users (id)
        ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE admin_audit_logs (
    id BIGINT NOT NULL AUTO_INCREMENT,
    admin_user_id BIGINT NOT NULL,
    action VARCHAR(128) NOT NULL,
    target_type VARCHAR(64) NOT NULL,
    target_id BIGINT NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    KEY idx_admin_audit_admin_created (admin_user_id, created_at),
    KEY idx_admin_audit_target (target_type, target_id),
    CONSTRAINT fk_admin_audit_admin_user
        FOREIGN KEY (admin_user_id) REFERENCES users (id)
        ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
