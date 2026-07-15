package com.harmonyocr.ai.service;

import com.harmonyocr.ai.config.AiByokProperties;
import com.harmonyocr.common.error.BusinessException;
import com.harmonyocr.common.error.ErrorCode;
import java.nio.charset.StandardCharsets;
import java.security.GeneralSecurityException;
import java.security.MessageDigest;
import java.security.SecureRandom;
import java.util.Base64;
import javax.crypto.Cipher;
import javax.crypto.spec.GCMParameterSpec;
import javax.crypto.spec.SecretKeySpec;
import org.springframework.stereotype.Service;

/**
 * AI BYOK 密钥加解密服务，属于 ai 模块。
 * 维护说明：使用运行时主密钥派生 AES-256-GCM key；只返回密文或内存明文，不记录 API Key。
 */
@Service
public class AiKeyCryptoService {

    private static final String FORMAT_PREFIX = "v1:";
    private static final int GCM_TAG_BITS = 128;
    private static final int IV_BYTES = 12;

    private final AiByokProperties properties;
    private final SecureRandom secureRandom = new SecureRandom();

    public AiKeyCryptoService(AiByokProperties properties) {
        this.properties = properties;
    }

    /**
     * 加密用户 API Key。
     * 参数 plaintextApiKey 只在内存中短暂存在；返回带版本号的 AES-GCM 密文。
     * 安全注意：未配置运行时主密钥时拒绝加密，避免降级为明文或固定密钥。
     */
    public String encrypt(String plaintextApiKey) {
        try {
            byte[] iv = new byte[IV_BYTES];
            secureRandom.nextBytes(iv);
            Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding");
            cipher.init(Cipher.ENCRYPT_MODE, keySpec(), new GCMParameterSpec(GCM_TAG_BITS, iv));
            byte[] encrypted = cipher.doFinal(plaintextApiKey.getBytes(StandardCharsets.UTF_8));
            return FORMAT_PREFIX
                    + Base64.getUrlEncoder().withoutPadding().encodeToString(iv)
                    + ":"
                    + Base64.getUrlEncoder().withoutPadding().encodeToString(encrypted);
        } catch (GeneralSecurityException ex) {
            throw new BusinessException(ErrorCode.INTERNAL_ERROR, "API key encryption failed");
        }
    }

    /**
     * 解密已保存的用户 API Key。
     * 参数 encryptedApiKey 必须是本服务生成的版本化密文；返回值只允许用于内存中的 provider 调用。
     */
    public String decrypt(String encryptedApiKey) {
        if (encryptedApiKey == null || !encryptedApiKey.startsWith(FORMAT_PREFIX)) {
            throw new BusinessException(ErrorCode.VALIDATION_ERROR, "Encrypted API key is not available");
        }
        String[] parts = encryptedApiKey.split(":", 3);
        if (parts.length != 3) {
            throw new BusinessException(ErrorCode.VALIDATION_ERROR, "Encrypted API key format is invalid");
        }
        try {
            byte[] iv = Base64.getUrlDecoder().decode(parts[1]);
            byte[] encrypted = Base64.getUrlDecoder().decode(parts[2]);
            Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding");
            cipher.init(Cipher.DECRYPT_MODE, keySpec(), new GCMParameterSpec(GCM_TAG_BITS, iv));
            return new String(cipher.doFinal(encrypted), StandardCharsets.UTF_8);
        } catch (IllegalArgumentException | GeneralSecurityException ex) {
            throw new BusinessException(ErrorCode.VALIDATION_ERROR, "Encrypted API key cannot be decrypted");
        }
    }

    /**
     * 判断运行时是否已配置可用于 BYOK 的主密钥。
     * 返回 true 表示可以加密保存用户 key；false 表示必须阻断真实 BYOK。
     */
    public boolean isConfigured() {
        return properties.encryptionSecret() != null && properties.encryptionSecret().length() >= 32;
    }

    private SecretKeySpec keySpec() {
        if (!isConfigured()) {
            throw new BusinessException(ErrorCode.VALIDATION_ERROR, "AI key encryption secret is not configured");
        }
        try {
            MessageDigest digest = MessageDigest.getInstance("SHA-256");
            byte[] key = digest.digest(properties.encryptionSecret().getBytes(StandardCharsets.UTF_8));
            return new SecretKeySpec(key, "AES");
        } catch (GeneralSecurityException ex) {
            throw new BusinessException(ErrorCode.INTERNAL_ERROR, "API key encryption key derivation failed");
        }
    }
}
