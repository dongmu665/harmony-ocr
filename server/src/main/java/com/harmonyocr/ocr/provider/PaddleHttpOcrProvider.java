package com.harmonyocr.ocr.provider;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.harmonyocr.common.error.BusinessException;
import com.harmonyocr.common.error.ErrorCode;
import com.harmonyocr.ocr.config.OcrProperties;
import com.harmonyocr.ocr.dto.OcrRequest;
import com.harmonyocr.ocr.dto.OcrResult;
import com.harmonyocr.ocr.dto.OcrTextBlockResponse;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.boot.web.client.RestTemplateBuilder;
import org.springframework.http.HttpEntity;
import org.springframework.http.HttpMethod;
import org.springframework.http.ResponseEntity;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestClientException;
import org.springframework.web.client.RestTemplate;

/**
 * PaddleOCR HTTP Provider 预留适配器，属于 ocr 模块。
 * 维护说明：本类只定义后端到独立 PaddleOCR 服务的 contract，不内置模型、Docker 镜像或 Python runtime；默认不会启用。
 */
@Component
@ConditionalOnProperty(prefix = "app.ocr", name = "provider", havingValue = "paddle-http")
public class PaddleHttpOcrProvider implements OcrProvider {

    private final OcrProperties properties;
    private final RestTemplate restTemplate;
    private final HttpClient httpClient;
    private final ObjectMapper objectMapper;

    public PaddleHttpOcrProvider(OcrProperties properties, RestTemplateBuilder restTemplateBuilder) {
        this.properties = properties;
        this.restTemplate = restTemplateBuilder
                .setConnectTimeout(Duration.ofMillis(properties.timeoutMs()))
                .setReadTimeout(Duration.ofMillis(properties.timeoutMs()))
                .build();
        this.httpClient = HttpClient.newBuilder()
                .connectTimeout(Duration.ofMillis(properties.timeoutMs()))
                .build();
        this.objectMapper = new ObjectMapper();
    }

    /**
     * 调用外置 PaddleOCR HTTP 服务。
     * 参数 request 包含已校验图片字节；返回值映射 providerName、engineName、duration、language、confidence、boundingBox 和 blocks。
     */
    @Override
    public OcrResult recognize(OcrRequest request) {
        if (!properties.enabled()) {
            throw new BusinessException(ErrorCode.OCR_FAILED, "OCR provider is disabled");
        }
        long start = System.nanoTime();
        try {
            PaddleRecognizeResponse response = postRecognize(request);
            if (response == null || isBlank(response.rawText())) {
                throw new BusinessException(ErrorCode.OCR_FAILED, "PaddleOCR result is empty");
            }
            long durationMs = response.durationMs() == null
                    ? Duration.ofNanos(System.nanoTime() - start).toMillis()
                    : response.durationMs();
            return new OcrResult(
                    providerName(),
                    blankToDefault(response.engineName(), engineName()),
                    blankToDefault(response.mode(), request.mode()),
                    response.rawText(),
                    durationMs,
                    blankToDefault(response.language(), request.language()),
                    response.confidence(),
                    response.boundingBox(),
                    response.blocks() == null ? List.of() : response.blocks(),
                    response.errorCode());
        } catch (BusinessException ex) {
            throw ex;
        } catch (RestClientException | IOException ex) {
            String causeType = ex.getCause() == null ? "unknown" : ex.getCause().getClass().getSimpleName();
            throw new BusinessException(ErrorCode.OCR_FAILED,
                    "PaddleOCR service unavailable: " + ex.getClass().getSimpleName() + "/" + causeType);
        } catch (InterruptedException ex) {
            Thread.currentThread().interrupt();
            throw new BusinessException(ErrorCode.OCR_TIMEOUT, "PaddleOCR service interrupted");
        }
    }

    /**
     * 检查外置 PaddleOCR 服务健康状态。
     * 返回值只表示 HTTP health endpoint 可达，不代表模型、语言包、性能或生产容量已经验收。
     */
    @Override
    public boolean isAvailable() {
        try {
            ResponseEntity<Map> response = restTemplate.exchange(
                    endpoint(properties.healthPath()),
                    HttpMethod.GET,
                    HttpEntity.EMPTY,
                    Map.class);
            return response.getStatusCode().is2xxSuccessful();
        } catch (RestClientException ex) {
            return false;
        }
    }

    /**
     * 返回外置 PaddleOCR HTTP 引擎标识。
     * 该值用于响应元数据和日志脱敏诊断，不包含服务地址或模型部署路径。
     */
    @Override
    public String engineName() {
        return "paddleocr-http";
    }

    /**
     * 返回外置 PaddleOCR provider 标识。
     * 该值只说明调用路径，不暴露健康检查地址、Base URL 或内部网络位置。
     */
    @Override
    public String providerName() {
        return "paddle-http";
    }

    private PaddleRecognizeResponse postRecognize(OcrRequest request) throws IOException, InterruptedException {
        String boundary = "----HarmonyOcrPaddle" + UUID.randomUUID().toString().replace("-", "");
        byte[] body = multipartBody(boundary, request);
        HttpRequest httpRequest = HttpRequest.newBuilder(URI.create(endpoint("/recognize")))
                .timeout(Duration.ofMillis(properties.timeoutMs()))
                .header("Content-Type", "multipart/form-data; boundary=" + boundary)
                .POST(HttpRequest.BodyPublishers.ofByteArray(body))
                .build();
        HttpResponse<String> response = httpClient.send(httpRequest, HttpResponse.BodyHandlers.ofString(StandardCharsets.UTF_8));
        if (response.statusCode() < 200 || response.statusCode() >= 300) {
            throw new BusinessException(ErrorCode.OCR_FAILED, "PaddleOCR service returned non-success");
        }
        return objectMapper.readValue(response.body(), PaddleRecognizeResponse.class);
    }

    /**
     * 构造受控 multipart 请求体。
     * 参数 request 包含本次图片字节和语言模式；返回值为 HTTP body，不包含用户原始文件名，避免向外置服务传播隐私命名。
     */
    private byte[] multipartBody(String boundary, OcrRequest request) throws IOException {
        ByteArrayOutputStream output = new ByteArrayOutputStream();
        writeTextPart(output, boundary, "contentType", request.contentType());
        writeTextPart(output, boundary, "language", request.language());
        writeTextPart(output, boundary, "mode", request.mode());
        writeFilePart(output, boundary, request.contentType(), request.content());
        output.write(("--" + boundary + "--\r\n").getBytes(StandardCharsets.UTF_8));
        return output.toByteArray();
    }

    private void writeTextPart(ByteArrayOutputStream output, String boundary, String name, String value) throws IOException {
        output.write(("--" + boundary + "\r\n").getBytes(StandardCharsets.UTF_8));
        output.write(("Content-Disposition: form-data; name=\"" + name + "\"\r\n\r\n").getBytes(StandardCharsets.UTF_8));
        output.write((blankToDefault(value, "") + "\r\n").getBytes(StandardCharsets.UTF_8));
    }

    private void writeFilePart(ByteArrayOutputStream output, String boundary, String contentType, byte[] content) throws IOException {
        output.write(("--" + boundary + "\r\n").getBytes(StandardCharsets.UTF_8));
        output.write("Content-Disposition: form-data; name=\"file\"; filename=\"image\"\r\n".getBytes(StandardCharsets.UTF_8));
        output.write(("Content-Type: " + blankToDefault(contentType, "application/octet-stream") + "\r\n\r\n").getBytes(StandardCharsets.UTF_8));
        output.write(content);
        output.write("\r\n".getBytes(StandardCharsets.UTF_8));
    }

    private String endpoint(String path) {
        String base = properties.serviceUrl().replaceAll("/+$", "");
        String normalizedPath = path == null || path.isBlank() ? "" : path;
        return normalizedPath.startsWith("/") ? base + normalizedPath : base + "/" + normalizedPath;
    }

    private String blankToDefault(String value, String defaultValue) {
        return isBlank(value) ? defaultValue : value;
    }

    private boolean isBlank(String value) {
        return value == null || value.isBlank();
    }

    private record PaddleRecognizeResponse(
            String rawText,
            Long durationMs,
            String language,
            String engineName,
            String mode,
            Double confidence,
            String boundingBox,
            List<OcrTextBlockResponse> blocks,
            String errorCode
    ) {
    }
}
