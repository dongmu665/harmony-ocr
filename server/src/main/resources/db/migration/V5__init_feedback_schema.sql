-- V1.1 用户反馈表：保存用户主动提交的问题类型、内容和处理状态。
-- 隐私边界：反馈归属用户可为空；后台展示和处理不得泄露 Token、密码、API Key 或 OCR 私密全文。
CREATE TABLE feedback (
    id BIGINT NOT NULL AUTO_INCREMENT,
    user_id BIGINT NULL,
    feedback_type VARCHAR(32) NOT NULL,
    content TEXT NOT NULL,
    contact VARCHAR(128) NULL,
    device_info VARCHAR(512) NULL,
    app_version VARCHAR(64) NULL,
    status VARCHAR(32) NOT NULL DEFAULT 'PENDING',
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    deleted TINYINT NOT NULL DEFAULT 0,
    PRIMARY KEY (id),
    KEY idx_feedback_user_created (user_id, created_at),
    KEY idx_feedback_status_created (status, created_at),
    KEY idx_feedback_type_created (feedback_type, created_at),
    CONSTRAINT fk_feedback_user
        FOREIGN KEY (user_id) REFERENCES users (id)
        ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
