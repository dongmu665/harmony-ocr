package com.harmonyocr.ai.provider;

import com.harmonyocr.ai.dto.AiAction;
import com.harmonyocr.ai.dto.AiActionResponse;
import com.harmonyocr.ai.dto.AiProviderRequest;
import com.harmonyocr.ai.config.MockAiProviderCondition;
import org.springframework.context.annotation.Conditional;
import org.springframework.stereotype.Component;

/**
 * Mock AI 供应商，属于 ai 模块。
 * 维护说明：V2.0-5 在无安全 BYOK/真实 provider 配置前使用该实现验证 contract，不调用网络，不泄露 OCR 原文。
 */
@Component
@Conditional(MockAiProviderCondition.class)
public class MockAiProvider implements AiProvider {

    private static final String PROVIDER_NAME = "mock-ai-provider";
    private static final String MODEL_NAME = "contract-mock-v2";
    private static final String DEGRADATION_REASON = "Real AI provider is not configured; mock contract response returned";

    /**
     * 生成不含原文的 mock 响应。
     * 参数 request 只用于计算输入长度和动作类型；返回值标记 degraded=true，提醒调用方这是兼容契约而非真实 AI 结果。
     */
    @Override
    public AiActionResponse process(AiProviderRequest request) {
        return degradedResponse(request, DEGRADATION_REASON);
    }

    /**
     * 生成指定降级原因的 mock 响应。
     * 参数 degradationReason 为脱敏原因，不得包含底层异常、prompt、OCR 原文或 API Key。
     */
    public AiActionResponse degradedResponse(AiProviderRequest request, String degradationReason) {
        return new AiActionResponse(
                request.action(),
                PROVIDER_NAME,
                MODEL_NAME,
                mockOutput(request.action(), request.targetLanguage()),
                safeLength(request.sourceText()),
                true,
                true,
                degradationReason,
                null);
    }

    private String mockOutput(AiAction action, String targetLanguage) {
        String suffix = action == AiAction.TRANSLATION && targetLanguage != null && !targetLanguage.isBlank()
                ? " target=" + targetLanguage.trim()
                : "";
        return "[MOCK " + action.name() + "] V2.0 AI provider contract response." + suffix;
    }

    private int safeLength(String value) {
        return value == null ? 0 : value.length();
    }
}
