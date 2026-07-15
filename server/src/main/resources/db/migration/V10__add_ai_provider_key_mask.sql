-- V1.2 BYOK 密钥遮罩字段迁移：增加前端可展示的脱敏 key 状态。
-- 安全边界：api_key_masked 只能保存不可还原的短遮罩，不允许写入完整 API Key。
ALTER TABLE ai_provider_configs
    ADD COLUMN api_key_masked VARCHAR(32) NULL AFTER api_key_fingerprint;
