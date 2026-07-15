package com.harmonyocr.ocr.config;

import org.springframework.boot.context.properties.ConfigurationProperties;

/**
 * 后端 OCR 配置，属于 ocr 模块。
 * 维护说明：仅保存 OCR Provider 的可执行文件、语言、超时、文件大小限制和可选服务地址，不承载密钥或第三方 API 参数。
 */
@ConfigurationProperties(prefix = "app.ocr")
public record OcrProperties(
        boolean enabled,
        String provider,
        String executable,
        String language,
        long timeoutMs,
        long maxSizeBytes,
        String serviceUrl,
        String healthPath
) {

    public OcrProperties {
        if (provider == null || provider.isBlank()) {
            provider = "windows";
        }
        if (executable == null || executable.isBlank()) {
            executable = "powershell.exe";
        }
        if (language == null || language.isBlank()) {
            language = "eng";
        }
        if (timeoutMs <= 0) {
            timeoutMs = 15000;
        }
        if (maxSizeBytes <= 0) {
            maxSizeBytes = 10 * 1024 * 1024L;
        }
        if (serviceUrl == null || serviceUrl.isBlank()) {
            serviceUrl = "http://127.0.0.1:8866";
        }
        if (healthPath == null || healthPath.isBlank()) {
            healthPath = "/health";
        }
    }
}
