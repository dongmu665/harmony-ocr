-- V2.0 手工会员订单表：记录后台人工开通会员的审计元数据。
-- 安全边界：表内不得保存支付凭据、银行卡号、私密联系方式或任何生产密钥。
CREATE TABLE manual_membership_orders (
    id BIGINT NOT NULL AUTO_INCREMENT,
    user_id BIGINT NOT NULL,
    admin_user_id BIGINT NOT NULL,
    membership_level VARCHAR(32) NOT NULL,
    ocr_quota INT NOT NULL,
    ai_quota INT NOT NULL,
    export_quota INT NOT NULL,
    order_status VARCHAR(64) NOT NULL,
    payment_provider VARCHAR(64) NOT NULL,
    note VARCHAR(512) NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    KEY idx_manual_orders_user_created (user_id, created_at),
    KEY idx_manual_orders_admin_created (admin_user_id, created_at),
    CONSTRAINT fk_manual_orders_user
        FOREIGN KEY (user_id) REFERENCES users (id)
        ON DELETE CASCADE,
    CONSTRAINT fk_manual_orders_admin_user
        FOREIGN KEY (admin_user_id) REFERENCES users (id)
        ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
