-- V1.2 BYOK 密钥加密字段迁移：为 AI Provider 配置增加密文、指纹和安全存储状态。
-- 安全边界：encrypted_api_key 只能保存后端加密结果，api_key_fingerprint 不得用于还原明文密钥。
ALTER TABLE ai_provider_configs
    ADD COLUMN encrypted_api_key TEXT NULL AFTER api_key_fingerprint;
