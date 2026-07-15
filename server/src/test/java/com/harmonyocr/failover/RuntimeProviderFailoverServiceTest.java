package com.harmonyocr.failover;

import com.harmonyocr.ai.dto.AiAction;
import com.harmonyocr.ai.dto.AiActionRequest;
import com.harmonyocr.ai.dto.AiActionResponse;
import com.harmonyocr.ai.dto.AiProviderRequest;
import com.harmonyocr.ai.config.AiProperties;
import com.harmonyocr.ai.provider.AiProvider;
import com.harmonyocr.ai.provider.AiFailoverProvider;
import com.harmonyocr.ai.provider.OpenAiCompatibleAiProvider;
import com.harmonyocr.ai.service.AiActionService;
import com.harmonyocr.common.error.BusinessException;
import com.harmonyocr.common.error.ErrorCode;
import com.harmonyocr.membership.service.MembershipService;
import com.harmonyocr.ocr.config.OcrProperties;
import com.harmonyocr.ocr.dto.OcrRequest;
import com.harmonyocr.ocr.dto.OcrResult;
import com.harmonyocr.ocr.dto.OcrTextBlockResponse;
import com.harmonyocr.ocr.provider.OcrProvider;
import com.harmonyocr.ocr.service.OcrRecognitionService;
import com.harmonyocr.record.dto.RecordResponse;
import com.harmonyocr.record.service.RecordService;
import com.sun.net.httpserver.HttpServer;
import java.io.IOException;
import java.net.InetSocketAddress;
import java.nio.charset.StandardCharsets;
import java.time.LocalDateTime;
import java.util.List;
import java.util.concurrent.atomic.AtomicReference;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;
import org.springframework.boot.web.client.RestTemplateBuilder;
import org.springframework.http.HttpHeaders;
import org.springframework.mock.env.MockEnvironment;
import org.springframework.mock.web.MockMultipartFile;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * 运行时 Provider 故障切换服务测试，属于 failover 模块。
 * 维护说明：使用内存 provider 证明 service 层启用 failover 后会从失败 provider 切到可用 provider，不访问真实模型、网络或用户隐私数据。
 */
class RuntimeProviderFailoverServiceTest {

    private HttpServer server;

    @AfterEach
    void stopServer() {
        if (server != null) {
            server.stop(0);
        }
    }

    @Test
    void ocrRecognitionServiceFallsBackWhenFailoverEnabled() {
        OcrRecognitionService service = new OcrRecognitionService(
                List.of(failingOcrProvider(), successfulOcrProvider()),
                ocrProperties(),
                new MockEnvironment().withProperty("app.ocr.failover-enabled", "true"));

        var response = service.recognize(pngFile(), "eng");

        assertThat(response.providerName()).isEqualTo("fallback-ocr");
        assertThat(response.engineName()).isEqualTo("fallback-engine");
        assertThat(response.rawText()).isEqualTo("runtime fallback OCR");
        assertThat(response.confidence()).isEqualTo(0.91);
        assertThat(response.boundingBox()).isEqualTo("{\"x\":1,\"y\":2,\"width\":3,\"height\":4}");
    }

    @Test
    void aiActionServiceFallsBackWhenFailoverEnabled() {
        RecordService recordService = mock(RecordService.class);
        MembershipService membershipService = mock(MembershipService.class);
        when(recordService.detail(7L, 11L)).thenReturn(new RecordResponse(
                11L,
                "Runtime",
                "camera",
                null,
                "raw text",
                "edited runtime text",
                "eng",
                "fallback-engine",
                10,
                false,
                null,
                null,
                null,
                List.of(),
                List.of(),
                List.of(),
                0,
                0,
                0,
                false));
        AiActionService service = new AiActionService(
                recordService,
                List.of(failingAiProvider(), successfulAiProvider()),
                membershipService,
                new MockEnvironment().withProperty("app.ai.failover-enabled", "true"));

        AiActionResponse response = service.process(7L, new AiActionRequest(11L, AiAction.SUMMARY, null, true));

        assertThat(response.providerName()).isEqualTo("fallback-ai");
        assertThat(response.outputText()).isEqualTo("runtime fallback AI");
        assertThat(response.degraded()).isFalse();
        verify(membershipService).consume(7L, "AI");
    }

    @Test
    void aiFailoverUsesLocalOpenAiCompatibleProviderAfterFailingPrimary() throws Exception {
        String localApiKey = "local-test-" + System.nanoTime();
        AtomicReference<String> authorizationHeader = new AtomicReference<>();
        server = startOpenAiCompatibleServer(authorizationHeader);
        AiFailoverProvider provider = new AiFailoverProvider(List.of(
                failingAiProvider(),
                new OpenAiCompatibleAiProvider(
                        new AiProperties(
                                "openai-compatible",
                                "http://127.0.0.1:" + server.getAddress().getPort() + "/v1",
                                localApiKey,
                                "runtime-failover-model",
                                30000),
                        new RestTemplateBuilder())));

        AiActionResponse response = provider.process(new AiProviderRequest(
                7L,
                11L,
                AiAction.TITLE,
                "Harmony OCR runtime failover smoke text.",
                null));

        assertThat(response.providerName()).isEqualTo("openai-compatible");
        assertThat(response.modelName()).isEqualTo("runtime-failover-model");
        assertThat(response.degraded()).isFalse();
        assertThat(response.outputText()).isEqualTo("runtime failover title");
        assertThat(authorizationHeader.get()).isEqualTo("Bearer " + localApiKey);
    }

    private OcrProvider failingOcrProvider() {
        return new OcrProvider() {
            /**
             * 模拟运行时主 OCR Provider 失败。
             * 方法故意抛出 OCR_FAILED，用于验证 service 层启用 failover 后会切到后备 provider。
             */
            @Override
            public OcrResult recognize(OcrRequest request) {
                throw new BusinessException(ErrorCode.OCR_FAILED, "primary failed");
            }

            @Override
            public boolean isAvailable() {
                return true;
            }

            /**
             * 返回主 provider 的测试引擎标识。
             * 该值用于区分失败主 provider 和成功后备 provider。
             */
            @Override
            public String engineName() {
                return "primary-engine";
            }

            /**
             * 返回主 provider 的测试来源标识。
             */
            @Override
            public String providerName() {
                return "primary-ocr";
            }
        };
    }

    private OcrProvider successfulOcrProvider() {
        return new OcrProvider() {
            /**
             * 模拟运行时后备 OCR Provider 成功。
             * 返回固定 OCR 文本、置信度和边界框，避免真实 OCR 依赖。
             */
            @Override
            public OcrResult recognize(OcrRequest request) {
                return new OcrResult(
                        "fallback-ocr",
                        "fallback-engine",
                        request.mode(),
                        "runtime fallback OCR",
                        9,
                        request.language(),
                        0.91,
                        "{\"x\":1,\"y\":2,\"width\":3,\"height\":4}",
                        List.of(new OcrTextBlockResponse(1, "runtime fallback OCR", 0.91, "{\"x\":1}")),
                        null);
            }

            @Override
            public boolean isAvailable() {
                return true;
            }

            /**
             * 返回后备 provider 的测试引擎标识。
             */
            @Override
            public String engineName() {
                return "fallback-engine";
            }

            /**
             * 返回后备 provider 的测试来源标识。
             */
            @Override
            public String providerName() {
                return "fallback-ocr";
            }
        };
    }

    private AiProvider failingAiProvider() {
        return request -> {
            throw new BusinessException(ErrorCode.INTERNAL_ERROR, "primary AI failed");
        };
    }

    private AiProvider successfulAiProvider() {
        return request -> new AiActionResponse(
                request.action(),
                "fallback-ai",
                "runtime-model",
                "runtime fallback AI",
                request.sourceText().length(),
                true,
                false,
                null,
                null);
    }

    private OcrProperties ocrProperties() {
        return new OcrProperties(true, "windows", "powershell.exe", "eng", 15000, 10_485_760, "http://127.0.0.1:8866", "/health");
    }

    private MockMultipartFile pngFile() {
        return new MockMultipartFile("file", "runtime.png", "image/png", validPng());
    }

    private byte[] validPng() {
        return new byte[]{
                (byte) 0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
                0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52
        };
    }

    private HttpServer startOpenAiCompatibleServer(AtomicReference<String> authorizationHeader) throws IOException {
        HttpServer httpServer = HttpServer.create(new InetSocketAddress("127.0.0.1", 0), 0);
        httpServer.createContext("/v1/chat/completions", exchange -> {
            authorizationHeader.set(exchange.getRequestHeaders().getFirst(HttpHeaders.AUTHORIZATION));
            byte[] response = """
                    {"choices":[{"message":{"role":"assistant","content":"runtime failover title"}}]}
                    """.getBytes(StandardCharsets.UTF_8);
            exchange.getResponseHeaders().set(HttpHeaders.CONTENT_TYPE, "application/json");
            exchange.sendResponseHeaders(200, response.length);
            exchange.getResponseBody().write(response);
            exchange.close();
        });
        httpServer.start();
        return httpServer;
    }
}
