package com.harmonyocr.ai.service;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.baomidou.mybatisplus.core.conditions.query.LambdaQueryWrapper;
import com.baomidou.mybatisplus.core.conditions.update.LambdaUpdateWrapper;
import com.harmonyocr.ai.dto.AiActionResponse;
import com.harmonyocr.ai.dto.AiProviderConfigRequest;
import com.harmonyocr.ai.dto.AiProviderConfigResponse;
import com.harmonyocr.ai.dto.AiProviderRequest;
import com.harmonyocr.ai.dto.AiProviderTestResponse;
import com.harmonyocr.ai.entity.AiProviderConfigEntity;
import com.harmonyocr.ai.mapper.AiProviderConfigMapper;
import com.harmonyocr.common.error.BusinessException;
import com.harmonyocr.common.error.ErrorCode;
import java.net.InetAddress;
import java.net.URI;
import java.net.URISyntaxException;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.time.LocalDateTime;
import java.util.HexFormat;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import org.springframework.boot.web.client.RestTemplateBuilder;
import org.springframework.http.HttpEntity;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.client.RestClientException;
import org.springframework.web.client.RestTemplate;

/**
 * AI Provider 配置服务，属于 ai 模块。
 * 维护说明：V2.0-6 保存 AES-GCM 密文、fingerprint 和脱敏元数据；真实连接测试只对安全允许的 provider 发起。
 */
@Service
public class AiProviderConfigService {

    private static final String SECURE_STORAGE_ENCRYPTED = "ENCRYPTED_AES_GCM";
    private static final String REAL_TEST_STATUS = "REAL_SUCCESS";

    private final AiProviderConfigMapper providerConfigMapper;
    private final AiKeyCryptoService keyCryptoService;
    private final RestTemplate restTemplate;
    private final ObjectMapper objectMapper = new ObjectMapper();

    public AiProviderConfigService(
            AiProviderConfigMapper providerConfigMapper,
            AiKeyCryptoService keyCryptoService,
            RestTemplateBuilder restTemplateBuilder) {
        this.providerConfigMapper = providerConfigMapper;
        this.keyCryptoService = keyCryptoService;
        this.restTemplate = restTemplateBuilder.build();
    }

    /**
     * 创建当前用户的 AI Provider 配置。
     * 参数 userId 来自认证上下文，request.apiKey 用于 fingerprint 和 AES-GCM 加密；返回脱敏配置。
     * 安全注意：没有运行时加密主密钥时拒绝保存，避免 BYOK 降级成明文或不可审计存储。
     */
    @Transactional
    public AiProviderConfigResponse create(Long userId, AiProviderConfigRequest request) {
        validateCreateRequest(request);
        String apiKey = requiredTrim(request.apiKey(), "apiKey");
        LocalDateTime now = LocalDateTime.now();
        AiProviderConfigEntity entity = new AiProviderConfigEntity();
        entity.setUserId(userId);
        entity.setProviderName(requiredTrim(request.providerName(), "providerName"));
        entity.setBaseUrl(validateProviderBaseUrl(request.baseUrl()));
        entity.setModelName(requiredTrim(request.modelName(), "modelName"));
        entity.setApiKeyFingerprint(fingerprint(apiKey));
        entity.setApiKeyMasked(maskedKey(apiKey));
        entity.setEncryptedApiKey(keyCryptoService.encrypt(apiKey));
        entity.setSecureStorageStatus(SECURE_STORAGE_ENCRYPTED);
        entity.setEnabled(request.enabled() == null || request.enabled());
        entity.setDefaultProvider(Boolean.TRUE.equals(request.defaultProvider()));
        entity.setDeleted(false);
        entity.setCreatedAt(now);
        entity.setUpdatedAt(now);
        providerConfigMapper.insert(entity);
        if (Boolean.TRUE.equals(entity.getDefaultProvider())) {
            clearOtherDefaultProviders(userId, entity.getId(), now);
        }
        return toResponse(entity);
    }

    /**
     * 查询当前用户未删除的 AI Provider 配置列表。
     * 参数 userId 来自认证上下文；返回按创建时间排序的脱敏配置列表。
     */
    public List<AiProviderConfigResponse> list(Long userId) {
        return providerConfigMapper.selectList(new LambdaQueryWrapper<AiProviderConfigEntity>()
                        .eq(AiProviderConfigEntity::getUserId, userId)
                        .eq(AiProviderConfigEntity::getDeleted, false)
                        .orderByDesc(AiProviderConfigEntity::getCreatedAt)
                        .orderByDesc(AiProviderConfigEntity::getId))
                .stream()
                .map(this::toResponse)
                .toList();
    }

    /**
     * 更新当前用户拥有的 AI Provider 配置。
     * 参数 request 可局部更新 provider 元数据和 key；返回脱敏配置。不存在或越权时返回 NOT_FOUND。
     * 安全注意：apiKey 替换会生成新密文和 fingerprint，不保留旧 key 或新 key 原文。
     */
    @Transactional
    public AiProviderConfigResponse update(Long userId, Long id, AiProviderConfigRequest request) {
        AiProviderConfigEntity entity = ownedActiveProvider(userId, id);
        if (request.providerName() != null) {
            entity.setProviderName(requiredTrim(request.providerName(), "providerName"));
        }
        if (request.baseUrl() != null) {
            entity.setBaseUrl(validateProviderBaseUrl(request.baseUrl()));
        }
        if (request.modelName() != null) {
            entity.setModelName(requiredTrim(request.modelName(), "modelName"));
        }
        if (request.apiKey() != null) {
            String apiKey = requiredTrim(request.apiKey(), "apiKey");
            entity.setApiKeyFingerprint(fingerprint(apiKey));
            entity.setApiKeyMasked(maskedKey(apiKey));
            entity.setEncryptedApiKey(keyCryptoService.encrypt(apiKey));
            entity.setSecureStorageStatus(SECURE_STORAGE_ENCRYPTED);
        }
        if (request.enabled() != null) {
            entity.setEnabled(request.enabled());
        }
        if (request.defaultProvider() != null) {
            entity.setDefaultProvider(request.defaultProvider());
        }
        entity.setUpdatedAt(LocalDateTime.now());
        providerConfigMapper.updateById(entity);
        if (Boolean.TRUE.equals(entity.getDefaultProvider())) {
            clearOtherDefaultProviders(userId, entity.getId(), entity.getUpdatedAt());
        }
        return toResponse(ownedActiveProvider(userId, id));
    }

    /**
     * 对当前用户 provider 执行测试连接。
     * 参数 id 必须属于当前用户；返回真实 loopback 调用或 HTTPS 配置校验结果。
     * 安全注意：只在内存中解密 API Key；HTTPS 外部目标会发送固定连接测试请求，loopback 仅用于本地兼容测试，任何响应都不得记录密钥或正文。
     */
    public AiProviderTestResponse testConnection(Long userId, Long id) {
        AiProviderConfigEntity entity = ownedActiveProvider(userId, id);
        if (!Boolean.TRUE.equals(entity.getEnabled())) {
            throw new BusinessException(ErrorCode.VALIDATION_ERROR, "Provider is disabled");
        }
        return testOpenAiCompatibleProvider(entity);
    }

    /**
     * 使用当前用户默认 BYOK Provider 执行 AI 动作。
     * 参数 request 只在内存中携带 OCR 文本；若用户未配置默认启用 provider，返回 Optional.empty 让调用方走全局 provider。
     * 安全注意：API Key 只在本方法内解密并放入 Authorization header，不写日志、不返回、不持久化明文。
     */
    public Optional<AiActionResponse> processWithDefaultProvider(Long userId, AiProviderRequest request) {
        AiProviderConfigEntity entity = defaultEnabledProvider(userId);
        if (entity == null) {
            return Optional.empty();
        }
        String apiKey = keyCryptoService.decrypt(entity.getEncryptedApiKey());
        try {
            HttpHeaders headers = new HttpHeaders();
            headers.setContentType(MediaType.APPLICATION_JSON);
            headers.setBearerAuth(apiKey);
            Map<String, Object> body = Map.of(
                    "model", entity.getModelName(),
                    "messages", List.of(
                            Map.of("role", "system", "content", systemPrompt(request)),
                            Map.of("role", "user", "content", AiPromptTemplate.userMessage(request.sourceText()))));
            ResponseEntity<String> response = restTemplate.postForEntity(
                    endpoint(entity.getBaseUrl(), "/chat/completions"),
                    new HttpEntity<>(body, headers),
                    String.class);
            String outputText = extractOutput(response.getBody());
            if (outputText.isBlank()) {
                return Optional.of(degradedActionResponse(entity, request, "BYOK provider returned empty output"));
            }
            return Optional.of(new AiActionResponse(
                    request.action(),
                    entity.getProviderName(),
                    entity.getModelName(),
                    outputText,
                    safeLength(request.sourceText()),
                    true,
                    false,
                    null,
                    null));
        } catch (Exception ex) {
            return Optional.of(degradedActionResponse(entity, request, "BYOK provider call failed"));
        }
    }

    /**
     * 使用当前运行时主密钥重新加密用户 provider 的 API Key。
     * 参数 id 必须属于当前用户；返回值保持脱敏，fingerprint 不变，密文因 AES-GCM 新 IV 而更新。
     * 安全注意：明文 key 只在当前方法内短暂存在，不写日志、不返回给 API、不落入文档或测试输出。
     */
    @Transactional
    public AiProviderConfigResponse reencrypt(Long userId, Long id) {
        AiProviderConfigEntity entity = ownedActiveProvider(userId, id);
        String apiKey = keyCryptoService.decrypt(entity.getEncryptedApiKey());
        entity.setEncryptedApiKey(keyCryptoService.encrypt(apiKey));
        entity.setSecureStorageStatus(SECURE_STORAGE_ENCRYPTED);
        entity.setUpdatedAt(LocalDateTime.now());
        providerConfigMapper.updateById(entity);
        return toResponse(ownedActiveProvider(userId, id));
    }

    /**
     * 软删除当前用户拥有的 AI Provider 配置。
     * 参数 id 必须属于当前用户；返回值为空。不存在或越权时返回 NOT_FOUND。
     */
    @Transactional
    public void delete(Long userId, Long id) {
        LocalDateTime now = LocalDateTime.now();
        int updated = providerConfigMapper.update(null, new LambdaUpdateWrapper<AiProviderConfigEntity>()
                .eq(AiProviderConfigEntity::getId, id)
                .eq(AiProviderConfigEntity::getUserId, userId)
                .eq(AiProviderConfigEntity::getDeleted, false)
                .set(AiProviderConfigEntity::getDeleted, true)
                .set(AiProviderConfigEntity::getDefaultProvider, false)
                .set(AiProviderConfigEntity::getDeletedAt, now)
                .set(AiProviderConfigEntity::getUpdatedAt, now));
        if (updated == 0) {
            throw new BusinessException(ErrorCode.NOT_FOUND);
        }
    }

    /**
     * 删除指定用户的 provider 配置，用于账号注销。
     * 参数 userId 来自账号注销编排；只处理该用户配置，不影响其他用户。
     */
    @Transactional
    public void deleteByUserId(Long userId) {
        LocalDateTime now = LocalDateTime.now();
        providerConfigMapper.update(null, new LambdaUpdateWrapper<AiProviderConfigEntity>()
                .eq(AiProviderConfigEntity::getUserId, userId)
                .set(AiProviderConfigEntity::getDeleted, true)
                .set(AiProviderConfigEntity::getDefaultProvider, false)
                .set(AiProviderConfigEntity::getDeletedAt, now)
                .set(AiProviderConfigEntity::getUpdatedAt, now));
    }

    private void validateCreateRequest(AiProviderConfigRequest request) {
        requiredTrim(request.providerName(), "providerName");
        validateProviderBaseUrl(request.baseUrl());
        requiredTrim(request.modelName(), "modelName");
        requiredTrim(request.apiKey(), "apiKey");
    }

    private AiProviderConfigEntity ownedActiveProvider(Long userId, Long id) {
        AiProviderConfigEntity entity = providerConfigMapper.selectOne(new LambdaQueryWrapper<AiProviderConfigEntity>()
                .eq(AiProviderConfigEntity::getId, id)
                .eq(AiProviderConfigEntity::getUserId, userId)
                .eq(AiProviderConfigEntity::getDeleted, false));
        if (entity == null) {
            throw new BusinessException(ErrorCode.NOT_FOUND);
        }
        return entity;
    }

    private AiProviderConfigEntity defaultEnabledProvider(Long userId) {
        return providerConfigMapper.selectOne(new LambdaQueryWrapper<AiProviderConfigEntity>()
                .eq(AiProviderConfigEntity::getUserId, userId)
                .eq(AiProviderConfigEntity::getDeleted, false)
                .eq(AiProviderConfigEntity::getEnabled, true)
                .eq(AiProviderConfigEntity::getDefaultProvider, true)
                .last("LIMIT 1"));
    }

    private void clearOtherDefaultProviders(Long userId, Long currentId, LocalDateTime now) {
        providerConfigMapper.update(null, new LambdaUpdateWrapper<AiProviderConfigEntity>()
                .eq(AiProviderConfigEntity::getUserId, userId)
                .eq(AiProviderConfigEntity::getDeleted, false)
                .ne(AiProviderConfigEntity::getId, currentId)
                .set(AiProviderConfigEntity::getDefaultProvider, false)
                .set(AiProviderConfigEntity::getUpdatedAt, now));
    }

    private String validateProviderBaseUrl(String value) {
        String baseUrl = requiredTrim(value, "baseUrl");
        try {
            URI uri = new URI(baseUrl);
            boolean https = "https".equalsIgnoreCase(uri.getScheme());
            boolean loopbackHttp = "http".equalsIgnoreCase(uri.getScheme()) && isLoopbackHost(uri.getHost());
            if ((!https && !loopbackHttp) || uri.getHost() == null || uri.getUserInfo() != null) {
                throw new BusinessException(
                        ErrorCode.VALIDATION_ERROR,
                        "baseUrl must be an https URL, or http loopback for local compatibility tests");
            }
        } catch (URISyntaxException ex) {
            throw new BusinessException(ErrorCode.VALIDATION_ERROR, "baseUrl must be a valid provider URL");
        }
        return baseUrl;
    }

    private AiProviderTestResponse testOpenAiCompatibleProvider(AiProviderConfigEntity entity) {
        String apiKey = keyCryptoService.decrypt(entity.getEncryptedApiKey());
        try {
            validateLiveTestTarget(entity.getBaseUrl());
            HttpHeaders headers = new HttpHeaders();
            headers.setContentType(MediaType.APPLICATION_JSON);
            headers.setBearerAuth(apiKey);
            Map<String, Object> request = Map.of(
                    "model", entity.getModelName(),
                    "messages", List.of(
                            Map.of("role", "system", "content", "Return a short connectivity confirmation."),
                            Map.of("role", "user", "content", "connection-test")));
            ResponseEntity<String> response = restTemplate.postForEntity(
                    endpoint(entity.getBaseUrl(), "/chat/completions"),
                    new HttpEntity<>(request, headers),
                    String.class);
            if (!response.getStatusCode().is2xxSuccessful()) {
                return degradedTestResponse(entity, "Provider connection failed with non-success status");
            }
            return new AiProviderTestResponse(
                    entity.getId(),
                    entity.getProviderName(),
                    REAL_TEST_STATUS,
                    false,
                    "Provider connection succeeded");
        } catch (RestClientException ex) {
            return degradedTestResponse(entity, "Provider connection failed");
        }
    }

    private void validateLiveTestTarget(String baseUrl) {
        try {
            URI uri = new URI(baseUrl);
            if (isLoopbackHost(uri.getHost())) {
                return;
            }
            if (!"https".equalsIgnoreCase(uri.getScheme())) {
                throw new BusinessException(ErrorCode.VALIDATION_ERROR, "external provider test requires https");
            }
            InetAddress address = InetAddress.getByName(uri.getHost());
            if (address.isAnyLocalAddress()
                    || address.isLoopbackAddress()
                    || address.isLinkLocalAddress()
                    || address.isSiteLocalAddress()
                    || address.isMulticastAddress()) {
                throw new BusinessException(ErrorCode.VALIDATION_ERROR, "provider host is not allowed for live test");
            }
        } catch (BusinessException ex) {
            throw ex;
        } catch (Exception ex) {
            // DNS failures are handled by the live request path and returned as REAL_FAILED.
        }
    }

    private AiProviderTestResponse degradedTestResponse(AiProviderConfigEntity entity, String message) {
        return new AiProviderTestResponse(entity.getId(), entity.getProviderName(), "REAL_FAILED", true, message);
    }

    private AiActionResponse degradedActionResponse(AiProviderConfigEntity entity, AiProviderRequest request, String message) {
        return new AiActionResponse(
                request.action(),
                entity.getProviderName(),
                entity.getModelName(),
                "[DEGRADED BYOK AI] Provider unavailable.",
                safeLength(request.sourceText()),
                true,
                true,
                message,
                "AI_PROVIDER_FAILED");
    }

    private String systemPrompt(AiProviderRequest request) {
        return AiPromptTemplate.systemPrompt(request);
    }

    private String extractOutput(String body) {
        if (body == null || body.isBlank()) {
            return "";
        }
        try {
            JsonNode root = objectMapper.readTree(stripEventStreamPrefix(body));
            return root.path("choices")
                    .path(0)
                    .path("message")
                    .path("content")
                    .asText("")
                    .trim();
        } catch (Exception ex) {
            return "";
        }
    }

    private String stripEventStreamPrefix(String body) {
        String trimmed = body.trim();
        if (!trimmed.startsWith("data:")) {
            return trimmed;
        }
        return trimmed.lines()
                .filter(line -> line.startsWith("data:"))
                .map(line -> line.substring("data:".length()).trim())
                .filter(line -> !line.isBlank() && !"[DONE]".equals(line))
                .findFirst()
                .orElse("");
    }

    private int safeLength(String value) {
        return value == null ? 0 : value.length();
    }

    private String endpoint(String baseUrl, String path) {
        String base = baseUrl.replaceAll("/+$", "");
        // 兼容用户把完整 OpenAI-compatible endpoint 填到 Base URL 的情况，避免重复拼接同一路径。
        if (base.endsWith(path)) {
            return base;
        }
        return path.startsWith("/") ? base + path : base + "/" + path;
    }

    private boolean isLoopbackBaseUrl(String baseUrl) {
        try {
            URI uri = new URI(baseUrl);
            return isLoopbackHost(uri.getHost());
        } catch (URISyntaxException ex) {
            return false;
        }
    }

    private boolean isLoopbackHost(String host) {
        if (host == null || host.isBlank()) {
            return false;
        }
        try {
            return InetAddress.getByName(host).isLoopbackAddress();
        } catch (Exception ex) {
            return false;
        }
    }

    private String requiredTrim(String value, String fieldName) {
        if (value == null || value.isBlank()) {
            throw new BusinessException(ErrorCode.VALIDATION_ERROR, fieldName + " is required");
        }
        return value.trim();
    }

    private String fingerprint(String apiKey) {
        try {
            MessageDigest digest = MessageDigest.getInstance("SHA-256");
            return HexFormat.of().formatHex(digest.digest(apiKey.getBytes(StandardCharsets.UTF_8)));
        } catch (NoSuchAlgorithmException ex) {
            throw new BusinessException(ErrorCode.INTERNAL_ERROR);
        }
    }

    private AiProviderConfigResponse toResponse(AiProviderConfigEntity entity) {
        return new AiProviderConfigResponse(
                entity.getId(),
                entity.getProviderName(),
                entity.getBaseUrl(),
                entity.getModelName(),
                entity.getApiKeyFingerprint(),
                entity.getApiKeyMasked(),
                entity.getEncryptedApiKey() != null && !entity.getEncryptedApiKey().isBlank(),
                entity.getSecureStorageStatus(),
                Boolean.TRUE.equals(entity.getEnabled()),
                Boolean.TRUE.equals(entity.getDefaultProvider()),
                entity.getCreatedAt(),
                entity.getUpdatedAt());
    }

    private String maskedKey(String apiKey) {
        String trimmed = apiKey == null ? "" : apiKey.trim();
        if (trimmed.length() <= 4) {
            return "****";
        }
        return "****" + trimmed.substring(trimmed.length() - 4);
    }
}
