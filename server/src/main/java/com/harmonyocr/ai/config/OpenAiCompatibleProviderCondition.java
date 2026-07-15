package com.harmonyocr.ai.config;

import org.springframework.context.annotation.Condition;
import org.springframework.context.annotation.ConditionContext;
import org.springframework.core.type.AnnotatedTypeMetadata;
import org.springframework.util.StringUtils;

/**
 * OpenAI-compatible Provider 启用条件，属于 ai 模块。
 * 维护说明：只根据环境变量映射后的配置判断是否启用真实 provider，不读取、记录或暴露 API Key 内容。
 */
public class OpenAiCompatibleProviderCondition implements Condition {

    /**
     * 判断是否启用真实 OpenAI-compatible provider。
     * 参数 context 提供 Spring Environment；当显式 provider 为 openai-compatible，或未显式指定 provider 但存在 API Key 时启用。
     */
    @Override
    public boolean matches(ConditionContext context, AnnotatedTypeMetadata metadata) {
        String provider = context.getEnvironment().getProperty("app.ai.provider", "");
        String apiKey = context.getEnvironment().getProperty("app.ai.api-key", "");
        return "openai-compatible".equalsIgnoreCase(provider)
                || (!StringUtils.hasText(provider) && StringUtils.hasText(apiKey));
    }
}
