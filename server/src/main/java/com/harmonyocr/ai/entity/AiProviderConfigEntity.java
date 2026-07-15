package com.harmonyocr.ai.entity;

import com.baomidou.mybatisplus.annotation.IdType;
import com.baomidou.mybatisplus.annotation.TableId;
import com.baomidou.mybatisplus.annotation.TableName;
import java.time.LocalDateTime;

/**
 * AI Provider 配置实体，属于 ai 模块。
 * 维护说明：该表保存 provider 元数据、API Key fingerprint 和 AES-GCM 密文；不得保存或返回 API Key 明文。
 */
@TableName("ai_provider_configs")
public class AiProviderConfigEntity {

    @TableId(type = IdType.AUTO)
    private Long id;
    private Long userId;
    private String providerName;
    private String baseUrl;
    private String modelName;
    private String apiKeyFingerprint;
    private String apiKeyMasked;
    private String encryptedApiKey;
    private String secureStorageStatus;
    private Boolean enabled;
    private Boolean defaultProvider;
    private Boolean deleted;
    private LocalDateTime createdAt;
    private LocalDateTime updatedAt;
    private LocalDateTime deletedAt;

    public Long getId() {
        return id;
    }

    public void setId(Long id) {
        this.id = id;
    }

    public Long getUserId() {
        return userId;
    }

    public void setUserId(Long userId) {
        this.userId = userId;
    }

    public String getProviderName() {
        return providerName;
    }

    public void setProviderName(String providerName) {
        this.providerName = providerName;
    }

    public String getBaseUrl() {
        return baseUrl;
    }

    public void setBaseUrl(String baseUrl) {
        this.baseUrl = baseUrl;
    }

    public String getModelName() {
        return modelName;
    }

    public void setModelName(String modelName) {
        this.modelName = modelName;
    }

    public String getApiKeyFingerprint() {
        return apiKeyFingerprint;
    }

    public void setApiKeyFingerprint(String apiKeyFingerprint) {
        this.apiKeyFingerprint = apiKeyFingerprint;
    }

    public String getApiKeyMasked() {
        return apiKeyMasked;
    }

    public void setApiKeyMasked(String apiKeyMasked) {
        this.apiKeyMasked = apiKeyMasked;
    }

    public String getEncryptedApiKey() {
        return encryptedApiKey;
    }

    public void setEncryptedApiKey(String encryptedApiKey) {
        this.encryptedApiKey = encryptedApiKey;
    }

    public String getSecureStorageStatus() {
        return secureStorageStatus;
    }

    public void setSecureStorageStatus(String secureStorageStatus) {
        this.secureStorageStatus = secureStorageStatus;
    }

    public Boolean getEnabled() {
        return enabled;
    }

    public void setEnabled(Boolean enabled) {
        this.enabled = enabled;
    }

    public Boolean getDefaultProvider() {
        return defaultProvider;
    }

    public void setDefaultProvider(Boolean defaultProvider) {
        this.defaultProvider = defaultProvider;
    }

    public Boolean getDeleted() {
        return deleted;
    }

    public void setDeleted(Boolean deleted) {
        this.deleted = deleted;
    }

    public LocalDateTime getCreatedAt() {
        return createdAt;
    }

    public void setCreatedAt(LocalDateTime createdAt) {
        this.createdAt = createdAt;
    }

    public LocalDateTime getUpdatedAt() {
        return updatedAt;
    }

    public void setUpdatedAt(LocalDateTime updatedAt) {
        this.updatedAt = updatedAt;
    }

    public LocalDateTime getDeletedAt() {
        return deletedAt;
    }

    public void setDeletedAt(LocalDateTime deletedAt) {
        this.deletedAt = deletedAt;
    }
}
