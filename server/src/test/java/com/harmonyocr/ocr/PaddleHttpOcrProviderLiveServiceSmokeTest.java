package com.harmonyocr.ocr;

import com.harmonyocr.ocr.config.OcrProperties;
import com.harmonyocr.ocr.dto.OcrRequest;
import com.harmonyocr.ocr.dto.OcrResult;
import com.harmonyocr.ocr.provider.PaddleHttpOcrProvider;
import java.io.IOException;
import java.io.InputStream;
import java.nio.file.Files;
import java.nio.file.Path;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable;
import org.springframework.boot.web.client.RestTemplateBuilder;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * PaddleOCR HTTP live service 冒烟测试，属于 ocr 模块。
 * 维护说明：仅在显式提供 PADDLE_HTTP_SERVICE_URL 时运行；图片必须由操作员指定，或来自已审查的测试资源。
 */
@EnabledIfEnvironmentVariable(named = "PADDLE_HTTP_SERVICE_URL", matches = "http://127\\.0\\.0\\.1:\\d+")
class PaddleHttpOcrProviderLiveServiceSmokeTest {

    private static final String REVIEWED_FIXTURE_RESOURCE = "/ocr/paddle-http-smoke-test.png";

    @Test
    void providerCallsLivePaddleCompatibleServiceAndMapsBlocks() throws IOException {
        String serviceUrl = System.getenv("PADDLE_HTTP_SERVICE_URL");
        PaddleHttpOcrProvider provider = new PaddleHttpOcrProvider(
                new OcrProperties(
                        true,
                        "paddle-http",
                        "unused",
                        "eng",
                        180000,
                        10 * 1024 * 1024L,
                        serviceUrl,
                        "/health"),
                new RestTemplateBuilder());

        assertThat(provider.isAvailable()).isTrue();

        byte[] image = liveFixtureImage();
        OcrResult result = provider.recognize(new OcrRequest(image, "image/png", "eng", "single-image"));

        assertThat(result.providerName()).isEqualTo("paddle-http");
        assertThat(result.engineName()).isEqualTo("paddleocr-http-service");
        assertThat(result.rawText()).isNotBlank();
        assertThat(result.confidence()).isNotNull();
        assertThat(result.blocks()).isNotEmpty();
        assertThat(result.blocks().getFirst().text()).isNotBlank();
        assertThat(result.blocks().getFirst().confidence()).isNotNull();
    }

    /**
     * 读取操作员显式指定的 PNG，或公开仓库中经审查的固定测试资源。
     * 安全注意：不会自动搜索开发日志、临时目录或仓库外的历史图片。
     *
     * @return 用于在线 OCR 冒烟测试的 PNG 字节
     * @throws IOException 读取图片失败时抛出
     */
    private byte[] liveFixtureImage() throws IOException {
        String operatorFixturePath = System.getenv("PADDLE_HTTP_FIXTURE_PATH");
        if (operatorFixturePath != null && !operatorFixturePath.isBlank()) {
            Path fixturePath = Path.of(operatorFixturePath).toAbsolutePath().normalize();
            assertThat(Files.isRegularFile(fixturePath))
                    .as("PADDLE_HTTP_FIXTURE_PATH must point to a regular PNG fixture")
                    .isTrue();
            return Files.readAllBytes(fixturePath);
        }

        try (InputStream inputStream = getClass().getResourceAsStream(REVIEWED_FIXTURE_RESOURCE)) {
            assertThat(inputStream)
                    .as("Set PADDLE_HTTP_FIXTURE_PATH or add the reviewed fixture under server/src/test/resources%s",
                            REVIEWED_FIXTURE_RESOURCE)
                    .isNotNull();
            return inputStream.readAllBytes();
        }
    }
}
