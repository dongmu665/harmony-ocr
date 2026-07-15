package com.harmonyocr.ai.provider;

import com.harmonyocr.ai.dto.AiActionResponse;
import com.harmonyocr.ai.dto.AiProviderRequest;

/**
 * AI 供应商统一接口，属于 ai 模块。
 * 维护说明：后续真实 OpenAI-compatible、BYOK 和多供应商故障切换都应通过该接口接入，避免 controller 直接处理密钥或 HTTP 细节。
 */
public interface AiProvider {

    /**
     * 执行 AI 文本处理动作。
     * 参数 request 包含当前用户、记录 ID、动作和内存中的 OCR 文本；返回 provider contract 响应。
     * 安全注意：实现类不得记录 sourceText 或任何 API Key。
     */
    AiActionResponse process(AiProviderRequest request);
}
