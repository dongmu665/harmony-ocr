-- V1.2 AI 运行时同意表：记录用户是否允许将 OCR 文本发送给第三方 AI Provider。
-- 隐私边界：只保存同意状态和时间，不保存 OCR 文本、prompt、API Key 或第三方响应。
CREATE TABLE ai_runtime_consents (
    user_id BIGINT NOT NULL,
    scope VARCHAR(64) NOT NULL,
    accepted BOOLEAN NOT NULL DEFAULT FALSE,
    accepted_at TIMESTAMP NULL,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (user_id, scope),
    CONSTRAINT fk_ai_runtime_consents_user
        FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE INDEX idx_ai_runtime_consents_updated ON ai_runtime_consents(updated_at);
