package com.harmonyocr.ai.provider;

import com.harmonyocr.ai.dto.AiActionResponse;
import com.harmonyocr.ai.dto.AiProviderRequest;
import com.harmonyocr.common.error.BusinessException;
import com.harmonyocr.common.error.ErrorCode;
import java.util.List;

/**
 * AI 故障切换 Provider，属于 ai 模块。
 * 维护说明：按顺序尝试多个 AI Provider，失败时只保留脱敏失败边界，不记录 prompt、OCR 原文、响应全文或 API Key。
 */
public class AiFailoverProvider implements AiProvider {

    private final List<AiProvider> providers;

    public AiFailoverProvider(List<AiProvider> providers) {
        this.providers = List.copyOf(providers);
    }

    /**
     * 依次执行 AI Provider。
     * 参数 request 包含内存中的 OCR 文本；返回第一个成功响应。所有 Provider 失败时抛出统一错误。
     */
    @Override
    public AiActionResponse process(AiProviderRequest request) {
        BusinessException lastFailure = null;
        for (AiProvider provider : providers) {
            try {
                return provider.process(request);
            } catch (BusinessException ex) {
                lastFailure = ex;
            }
        }
        if (lastFailure != null) {
            throw new BusinessException(lastFailure.getErrorCode(), "All AI providers failed");
        }
        throw new BusinessException(ErrorCode.INTERNAL_ERROR, "No AI providers configured");
    }
}
