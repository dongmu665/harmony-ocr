package com.harmonyocr.ocr.provider;

import com.harmonyocr.common.error.BusinessException;
import com.harmonyocr.common.error.ErrorCode;
import com.harmonyocr.ocr.config.OcrProperties;
import com.harmonyocr.ocr.dto.OcrRequest;
import com.harmonyocr.ocr.dto.OcrResult;
import com.harmonyocr.ocr.dto.OcrTextBlockResponse;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Duration;
import java.util.List;
import java.util.Locale;
import java.util.concurrent.TimeUnit;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.stereotype.Component;

/**
 * Tesseract CLI OCR Provider，属于 ocr 模块。
 * 维护说明：通过 ProcessBuilder 直接调用本机或容器内 tesseract，可执行文件路径来自配置；不拼接 shell 字符串，不记录图片内容或 OCR 全文。
 */
@Component
@ConditionalOnProperty(prefix = "app.ocr", name = "provider", havingValue = "tesseract")
public class TesseractOcrProvider implements OcrProvider {

    private static final int STDERR_LIMIT = 256;

    private final OcrProperties properties;

    public TesseractOcrProvider(OcrProperties properties) {
        this.properties = properties;
    }

    /**
     * 使用 Tesseract 对已校验图片执行真实 OCR。
     * 可能抛出 OCR_FAILED 或 OCR_TIMEOUT；临时文件会在 finally 中删除，避免长期保存用户图片。
     */
    @Override
    public OcrResult recognize(OcrRequest request) {
        if (!properties.enabled()) {
            throw new BusinessException(ErrorCode.OCR_FAILED, "OCR provider is disabled");
        }
        Path input = null;
        long start = System.nanoTime();
        try {
            input = Files.createTempFile("harmony-ocr-", extension(request.contentType()));
            Files.write(input, request.content());
            ProcessBuilder builder = new ProcessBuilder(
                    properties.executable(),
                    input.toString(),
                    "stdout",
                    "-l",
                    safeLanguage(request.language()),
                    "--psm",
                    "6");
            Process process = builder.start();
            boolean finished = process.waitFor(properties.timeoutMs(), TimeUnit.MILLISECONDS);
            if (!finished) {
                process.destroyForcibly();
                throw new BusinessException(ErrorCode.OCR_TIMEOUT);
            }
            String stdout = new String(process.getInputStream().readAllBytes(), StandardCharsets.UTF_8).trim();
            String stderr = safeProcessError(process.getErrorStream().readAllBytes());
            if (process.exitValue() != 0) {
                throw new BusinessException(ErrorCode.OCR_FAILED, stderr.isBlank() ? "OCR provider failed" : stderr);
            }
            if (stdout.isBlank()) {
                throw new BusinessException(ErrorCode.OCR_FAILED, "OCR result is empty");
            }
            long durationMs = Duration.ofNanos(System.nanoTime() - start).toMillis();
            return new OcrResult(
                    providerName(),
                    engineName(),
                    request.mode(),
                    stdout,
                    durationMs,
                    safeLanguage(request.language()),
                    null,
                    null,
                    List.of(new OcrTextBlockResponse(1, stdout, null, null)),
                    null);
        } catch (BusinessException ex) {
            throw ex;
        } catch (IOException ex) {
            throw new BusinessException(ErrorCode.OCR_FAILED, "OCR provider is unavailable");
        } catch (InterruptedException ex) {
            Thread.currentThread().interrupt();
            throw new BusinessException(ErrorCode.OCR_TIMEOUT);
        } finally {
            if (input != null) {
                try {
                    Files.deleteIfExists(input);
                } catch (IOException ignored) {
                }
            }
        }
    }

    /**
     * 检查 tesseract 命令是否可调用。
     */
    @Override
    public boolean isAvailable() {
        try {
            Process process = new ProcessBuilder(properties.executable(), "--version").start();
            boolean finished = process.waitFor(3000, TimeUnit.MILLISECONDS);
            if (!finished) {
                process.destroyForcibly();
                return false;
            }
            return process.exitValue() == 0;
        } catch (IOException | InterruptedException ex) {
            if (ex instanceof InterruptedException) {
                Thread.currentThread().interrupt();
            }
            return false;
        }
    }

    /**
     * 返回 Tesseract 引擎标识。
     * 该值用于客户端展示和诊断，不包含本机可执行文件路径。
     */
    @Override
    public String engineName() {
        return "tesseract";
    }

    /**
     * 返回 Tesseract provider 标识。
     * 该值只说明识别来源，不暴露运行环境或临时文件路径。
     */
    @Override
    public String providerName() {
        return "tesseract";
    }

    private String safeLanguage(String language) {
        String candidate = language == null || language.isBlank() ? properties.language() : language;
        return candidate.replaceAll("[^A-Za-z0-9_+.-]", "").toLowerCase(Locale.ROOT);
    }

    private String extension(String contentType) {
        return switch (contentType) {
            case "image/jpeg" -> ".jpg";
            case "image/webp" -> ".webp";
            default -> ".png";
        };
    }

    private String safeProcessError(byte[] stderrBytes) {
        String value = new String(stderrBytes, StandardCharsets.UTF_8).replaceAll("[\\r\\n]+", " ").trim();
        if (value.length() > STDERR_LIMIT) {
            return value.substring(0, STDERR_LIMIT);
        }
        return value;
    }
}
