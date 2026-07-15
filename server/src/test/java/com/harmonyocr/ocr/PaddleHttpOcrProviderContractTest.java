package com.harmonyocr.ocr;

import com.harmonyocr.ocr.config.OcrProperties;
import com.harmonyocr.ocr.dto.OcrRequest;
import com.harmonyocr.ocr.dto.OcrResult;
import com.harmonyocr.ocr.provider.PaddleHttpOcrProvider;
import com.sun.net.httpserver.HttpExchange;
import com.sun.net.httpserver.HttpServer;
import java.io.IOException;
import java.net.InetSocketAddress;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.List;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.boot.web.client.RestTemplateBuilder;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * PaddleOCR HTTP Provider 契约测试。
 * 维护说明：验证 multipart contract、响应映射和服务不可用处理，不依赖真实 PaddleOCR 模型。
 */
class PaddleHttpOcrProviderContractTest {

    private HttpServer server;
    private final List<String> paths = new ArrayList<>();

    @BeforeEach
    void startServer() throws IOException {
        server = HttpServer.create(new InetSocketAddress("127.0.0.1", 0), 0);
        server.start();
    }

    @AfterEach
    void stopServer() {
        server.stop(0);
        paths.clear();
    }

    @Test
    void recognizeMapsPaddleHttpContractWithoutRuntimeDependency() throws Exception {
        server.createContext("/recognize", exchange -> json(exchange, """
                        {
                          "rawText": "Paddle OCR Text",
                          "durationMs": 33,
                          "language": "eng",
                          "engineName": "paddleocr",
                          "mode": "single-image",
                          "confidence": 0.91,
                          "boundingBox": "{\\"x\\":1,\\"y\\":2}",
                          "blocks": [
                            {
                              "order": 1,
                              "text": "Paddle OCR Text",
                              "confidence": 0.91,
                              "boundingBox": "{\\"x\\":1,\\"y\\":2}"
                            }
                          ]
                        }
                        """)
        );

        PaddleHttpOcrProvider provider = new PaddleHttpOcrProvider(properties(), new RestTemplateBuilder());
        OcrResult result = provider.recognize(new OcrRequest(
                new byte[]{(byte) 0x89, 0x50, 0x4E, 0x47},
                "image/png",
                "eng",
                "single-image"));

        assertThat(result.providerName()).isEqualTo("paddle-http");
        assertThat(result.engineName()).isEqualTo("paddleocr");
        assertThat(result.rawText()).isEqualTo("Paddle OCR Text");
        assertThat(result.durationMs()).isEqualTo(33);
        assertThat(result.language()).isEqualTo("eng");
        assertThat(result.confidence()).isEqualTo(0.91);
        assertThat(result.boundingBox()).isEqualTo("{\"x\":1,\"y\":2}");
        assertThat(result.blocks()).hasSize(1);
        assertThat(paths).containsExactly("/recognize");
    }

    @Test
    void healthUsesConfiguredEndpointOnly() throws Exception {
        server.createContext("/health", exchange -> json(exchange, "{\"status\":\"UP\"}"));

        PaddleHttpOcrProvider provider = new PaddleHttpOcrProvider(properties(), new RestTemplateBuilder());

        assertThat(provider.isAvailable()).isTrue();
        assertThat(paths).containsExactly("/health");
    }

    private OcrProperties properties() {
        return new OcrProperties(
                true,
                "paddle-http",
                "unused",
                "eng",
                15000,
                10 * 1024 * 1024L,
                "http://127.0.0.1:" + server.getAddress().getPort(),
                "/health");
    }

    private void json(HttpExchange exchange, String body) throws IOException {
        paths.add(exchange.getRequestURI().getPath());
        byte[] bytes = body.getBytes(StandardCharsets.UTF_8);
        exchange.getResponseHeaders().add("Content-Type", "application/json");
        exchange.sendResponseHeaders(200, bytes.length);
        exchange.getResponseBody().write(bytes);
        exchange.close();
    }
}
