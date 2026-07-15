package com.harmonyocr.ocr.provider;

import com.harmonyocr.common.error.BusinessException;
import com.harmonyocr.common.error.ErrorCode;
import com.harmonyocr.ocr.dto.OcrRequest;
import com.harmonyocr.ocr.dto.OcrResult;
import java.util.List;

/**
 * OCR 故障切换 Provider，属于 ocr 模块。
 * 维护说明：按顺序尝试多个 OCR Provider，某个供应商失败时只使用脱敏错误码继续尝试，不记录图片内容或 OCR 全文。
 */
public class OcrFailoverProvider implements OcrProvider {

    private final List<OcrProvider> providers;

    public OcrFailoverProvider(List<OcrProvider> providers) {
        this.providers = List.copyOf(providers);
    }

    /**
     * 依次调用可用 OCR Provider。
     * 参数 request 为已校验图片请求；返回第一个成功结果。所有 Provider 失败时返回 OCR_FAILED，不暴露底层原始错误。
     */
    @Override
    public OcrResult recognize(OcrRequest request) {
        BusinessException lastFailure = null;
        for (OcrProvider provider : providers) {
            if (!provider.isAvailable()) {
                continue;
            }
            try {
                return provider.recognize(request);
            } catch (BusinessException ex) {
                lastFailure = ex;
            }
        }
        if (lastFailure != null && lastFailure.getErrorCode() == ErrorCode.OCR_TIMEOUT) {
            throw new BusinessException(ErrorCode.OCR_TIMEOUT, "All OCR providers timed out or failed");
        }
        throw new BusinessException(ErrorCode.OCR_FAILED, "All OCR providers failed");
    }

    /**
     * 检查是否至少有一个 OCR Provider 可用。
     * 返回值用于健康检查和部署 readiness，不触发用户图片识别。
     */
    @Override
    public boolean isAvailable() {
        return providers.stream().anyMatch(OcrProvider::isAvailable);
    }

    /**
     * 返回故障切换包装器的引擎标识。
     * 该值用于响应元数据和健康诊断，不暴露具体失败 provider 的内部细节。
     */
    @Override
    public String engineName() {
        return "ocr-failover";
    }

    /**
     * 返回故障切换包装器的 provider 标识。
     * 该值不代表单一底层供应商，只表示本次识别经过 failover 编排。
     */
    @Override
    public String providerName() {
        return "ocr-failover";
    }
}
