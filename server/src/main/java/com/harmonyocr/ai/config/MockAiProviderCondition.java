package com.harmonyocr.ai.config;

import org.springframework.context.annotation.Condition;
import org.springframework.context.annotation.ConditionContext;
import org.springframework.core.type.AnnotatedTypeMetadata;
import org.springframework.util.StringUtils;

/**
 * Mock AI Provider 启用条件，属于 ai 模块。
 * 维护说明：没有真实 provider 配置或显式选择 mock 时启用降级实现，避免缺少本地 API 环境时启动失败。
 */
public class MockAiProviderCondition implements Condition {

    /**
     * 判断是否启用 mock provider。
     * 参数 context 提供 Spring Environment；显式 provider=mock 或未指定 provider 且没有 API Key 时启用。
     */
    @Override
    public boolean matches(ConditionContext context, AnnotatedTypeMetadata metadata) {
        String provider = context.getEnvironment().getProperty("app.ai.provider", "");
        String apiKey = context.getEnvironment().getProperty("app.ai.api-key", "");
        return "mock".equalsIgnoreCase(provider)
                || (!StringUtils.hasText(provider) && !StringUtils.hasText(apiKey));
    }
}
