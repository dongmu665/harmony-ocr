package com.harmonyocr.ai;

import com.harmonyocr.ai.config.AiProperties;
import com.harmonyocr.ai.dto.AiAction;
import com.harmonyocr.ai.dto.AiActionResponse;
import com.harmonyocr.ai.dto.AiProviderRequest;
import com.harmonyocr.ai.provider.OpenAiCompatibleAiProvider;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable;
import org.springframework.boot.web.client.RestTemplateBuilder;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * OpenAI-compatible 本地环境 smoke test，属于 ai 模块。
 * 维护说明：仅在当前进程提供 OPENAI_BASE_URL、OPENAI_API_KEY、OPENAI_MODEL 时运行；测试不得输出 API Key、prompt 或完整响应。
 */
class OpenAiCompatibleAiProviderEnvSmokeTest {

    @Test
    @EnabledIfEnvironmentVariable(named = "OPENAI_BASE_URL", matches = ".+")
    @EnabledIfEnvironmentVariable(named = "OPENAI_API_KEY", matches = ".+")
    @EnabledIfEnvironmentVariable(named = "OPENAI_MODEL", matches = ".+")
    void providerCallsLocalOpenAiCompatibleApiFromTemporaryEnvironment() {
        OpenAiCompatibleAiProvider provider = new OpenAiCompatibleAiProvider(
                new AiProperties(
                        "openai-compatible",
                        System.getenv("OPENAI_BASE_URL"),
                        System.getenv("OPENAI_API_KEY"),
                        System.getenv("OPENAI_MODEL"),
                        30000),
                new RestTemplateBuilder());

        AiActionResponse response = provider.process(new AiProviderRequest(
                1L,
                2L,
                AiAction.TITLE,
                "Harmony OCR local smoke text.",
                null));

        assertThat(response.providerName()).isEqualTo("openai-compatible");
        assertThat(response.modelName()).isEqualTo(System.getenv("OPENAI_MODEL"));
        assertThat(response.degraded()).isFalse();
        assertThat(response.outputText()).isNotBlank();
        assertThat(response.outputText().length()).isLessThan(500);
    }
}
