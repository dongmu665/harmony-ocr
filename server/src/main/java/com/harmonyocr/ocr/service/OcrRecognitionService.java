package com.harmonyocr.ocr.service;

import com.harmonyocr.common.error.BusinessException;
import com.harmonyocr.common.error.ErrorCode;
import com.harmonyocr.file.validation.FileTypeDetector;
import com.harmonyocr.ocr.config.OcrProperties;
import com.harmonyocr.ocr.dto.OcrHealthResponse;
import com.harmonyocr.ocr.dto.OcrRequest;
import com.harmonyocr.ocr.dto.OcrRecognizeResponse;
import com.harmonyocr.ocr.dto.OcrResult;
import com.harmonyocr.ocr.provider.OcrFailoverProvider;
import com.harmonyocr.ocr.provider.OcrProvider;
import java.io.IOException;
import java.util.List;
import java.util.Locale;
import java.util.Set;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.core.env.Environment;
import org.springframework.stereotype.Service;
import org.springframework.web.multipart.MultipartFile;

/**
 * 后端 OCR 识别服务，属于 ocr 模块。
 * 维护说明：作为 V1.0 端侧 CoreVisionKit 不可用时的真实 OCR fallback，只处理当前请求图片，不持久化图片或 OCR 全文。
 */
@Service
public class OcrRecognitionService {

    private static final Set<String> ALLOWED_IMAGE_TYPES = Set.of("image/jpeg", "image/png", "image/webp");
    private static final String MODE_SINGLE_IMAGE = "single-image";

    private final OcrProvider ocrProvider;
    private final OcrProperties properties;

    @Autowired
    public OcrRecognitionService(List<OcrProvider> ocrProviders, OcrProperties properties, Environment environment) {
        this.ocrProvider = selectProvider(ocrProviders, environment);
        this.properties = properties;
    }

    public OcrRecognitionService(OcrProvider ocrProvider, OcrProperties properties) {
        this(List.of(ocrProvider), properties, null);
    }

    /**
     * 识别 multipart 图片。
     * 参数 file 必须为 JPEG/PNG/WebP 图片，language 为可选 OCR 语言；返回值为真实 OCR Provider 的结果。
     */
    public OcrRecognizeResponse recognize(MultipartFile file, String language) {
        byte[] content = validateAndReadImage(file);
        String contentType = normalizedContentType(file.getContentType());
        String normalizedLanguage = language == null || language.isBlank() ? properties.language() : language;
        OcrResult result = ocrProvider.recognize(new OcrRequest(content, contentType, normalizedLanguage, MODE_SINGLE_IMAGE));
        return toResponse(result);
    }

    /**
     * 返回 OCR Provider 健康状态。
     */
    public OcrHealthResponse health() {
        return new OcrHealthResponse(ocrProvider.isAvailable(), ocrProvider.engineName());
    }

    private byte[] validateAndReadImage(MultipartFile file) {
        if (file == null || file.isEmpty()) {
            throw new BusinessException(ErrorCode.VALIDATION_ERROR, "file must not be empty");
        }
        String contentType = normalizedContentType(file.getContentType());
        if (!ALLOWED_IMAGE_TYPES.contains(contentType)) {
            throw new BusinessException(ErrorCode.FILE_TYPE_NOT_ALLOWED);
        }
        if (file.getSize() > properties.maxSizeBytes()) {
            throw new BusinessException(ErrorCode.FILE_TOO_LARGE);
        }
        try {
            byte[] content = file.getBytes();
            FileTypeDetector.requireContentMatches(contentType, content);
            return content;
        } catch (BusinessException ex) {
            throw ex;
        } catch (IOException ex) {
            throw new BusinessException(ErrorCode.OCR_FAILED, "OCR image read failed");
        }
    }

    private String normalizedContentType(String contentType) {
        if (contentType == null || contentType.isBlank()) {
            throw new BusinessException(ErrorCode.FILE_TYPE_NOT_ALLOWED);
        }
        return contentType.trim().toLowerCase(Locale.ROOT);
    }

    /**
     * 将 Provider 结果映射为对外 API 响应。
     * 返回值保留旧字段 ocrEngine，同时新增 providerName、engineName、mode、confidence、boundingBox 和 errorCode。
     */
    private OcrRecognizeResponse toResponse(OcrResult result) {
        String engineName = blankToDefault(result.engineName(), ocrProvider.engineName());
        return new OcrRecognizeResponse(
                result.rawText(),
                result.rawText(),
                result.durationMs(),
                result.language(),
                engineName,
                blankToDefault(result.providerName(), ocrProvider.providerName()),
                engineName,
                blankToDefault(result.mode(), MODE_SINGLE_IMAGE),
                result.confidence(),
                result.boundingBox(),
                result.errorCode(),
                result.blocks());
    }

    private String blankToDefault(String value, String defaultValue) {
        return value == null || value.isBlank() ? defaultValue : value;
    }

    /**
     * 根据运行时配置选择 OCR Provider。
     * 参数 ocrProviders 来自 Spring 容器；当 app.ocr.failover-enabled=true 时包装为顺序 failover，否则沿用单 provider 行为。
     */
    private OcrProvider selectProvider(List<OcrProvider> ocrProviders, Environment environment) {
        if (ocrProviders == null || ocrProviders.isEmpty()) {
            throw new BusinessException(ErrorCode.OCR_FAILED, "OCR provider is not configured");
        }
        boolean failoverEnabled = environment != null
                && environment.getProperty("app.ocr.failover-enabled", Boolean.class, false);
        if (failoverEnabled && ocrProviders.size() > 1) {
            return new OcrFailoverProvider(ocrProviders);
        }
        return ocrProviders.getFirst();
    }
}
