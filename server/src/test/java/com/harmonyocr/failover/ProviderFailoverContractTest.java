package com.harmonyocr.failover;

import com.harmonyocr.ai.dto.AiAction;
import com.harmonyocr.ai.dto.AiActionResponse;
import com.harmonyocr.ai.dto.AiProviderRequest;
import com.harmonyocr.ai.provider.AiFailoverProvider;
import com.harmonyocr.ai.provider.AiProvider;
import com.harmonyocr.common.error.BusinessException;
import com.harmonyocr.common.error.ErrorCode;
import com.harmonyocr.ocr.dto.OcrRequest;
import com.harmonyocr.ocr.dto.OcrResult;
import com.harmonyocr.ocr.provider.OcrFailoverProvider;
import com.harmonyocr.ocr.provider.OcrProvider;
import java.nio.charset.StandardCharsets;
import java.util.List;
import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * Provider 故障切换契约测试，属于 failover 模块。
 * 维护说明：使用内存 fake provider 验证失败隔离，不调用真实 OCR、AI 网络或本地模型。
 */
class ProviderFailoverContractTest {

    @Test
    void ocrFailoverSkipsFailedPrimaryProviderAndUsesHealthyFallback() {
        OcrFailoverProvider provider = new OcrFailoverProvider(List.of(
                failingOcrProvider("primary-ocr"),
                successfulOcrProvider("fallback-ocr")));

        OcrResult result = provider.recognize(new OcrRequest(
                "image".getBytes(StandardCharsets.UTF_8),
                "image/png",
                "eng",
                "single-image"));

        assertThat(result.providerName()).isEqualTo("fallback-ocr");
        assertThat(result.engineName()).isEqualTo("fallback-ocr-engine");
        assertThat(result.rawText()).isEqualTo("fallback text");
        assertThat(result.errorCode()).isNull();
    }

    @Test
    void aiFailoverSkipsFailedPrimaryProviderAndUsesMockFallback() {
        AiFailoverProvider provider = new AiFailoverProvider(List.of(
                failingAiProvider(),
                successfulAiProvider()));

        AiActionResponse response = provider.process(new AiProviderRequest(
                1L,
                2L,
                AiAction.SUMMARY,
                "sample",
                null));

        assertThat(response.providerName()).isEqualTo("fallback-ai-provider");
        assertThat(response.outputText()).contains("fallback");
        assertThat(response.errorCode()).isNull();
    }

    private OcrProvider failingOcrProvider(String providerName) {
        return new OcrProvider() {
            /**
             * 模拟主 OCR Provider 识别失败。
             * 参数 request 不读取内容；方法故意抛出业务异常以验证 failover 会继续尝试后备 provider。
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
             * 返回失败 provider 的测试引擎名。
             * 该值只用于断言，不代表真实 OCR 引擎。
             */
            @Override
            public String engineName() {
                return providerName + "-engine";
            }

            /**
             * 返回失败 provider 的测试标识。
             * 该值用于确认 fallback 没有错误返回主 provider。
             */
            @Override
            public String providerName() {
                return providerName;
            }
        };
    }

    private OcrProvider successfulOcrProvider(String providerName) {
        return new OcrProvider() {
            /**
             * 模拟后备 OCR Provider 成功识别。
             * 返回固定文本，避免测试依赖真实图片或外部 OCR 服务。
             */
            @Override
            public OcrResult recognize(OcrRequest request) {
                return new OcrResult(
                        providerName,
                        providerName + "-engine",
                        request.mode(),
                        "fallback text",
                        12,
                        request.language(),
                        null,
                        null,
                        List.of(),
                        null);
            }

            @Override
            public boolean isAvailable() {
                return true;
            }

            /**
             * 返回后备 provider 的测试引擎名。
             * 该值用于断言最终结果来自 fallback。
             */
            @Override
            public String engineName() {
                return providerName + "-engine";
            }

            /**
             * 返回后备 provider 的测试标识。
             * 该值用于断言故障切换后的 provider 来源。
             */
            @Override
            public String providerName() {
                return providerName;
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
                "fallback-ai-provider",
                "fallback-model",
                "fallback response",
                request.sourceText().length(),
                true,
                true,
                "primary failed over to fallback",
                null);
    }
}
