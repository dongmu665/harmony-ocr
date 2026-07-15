package com.harmonyocr.ocr.provider;

import com.harmonyocr.ocr.dto.OcrRequest;
import com.harmonyocr.ocr.dto.OcrResult;

/**
 * 后端真实 OCR Provider 抽象，属于 ocr 模块。
 * 维护说明：实现必须对图片内容执行真实识别，不允许返回固定文本、Mock 文本或基于文件名的伪结果；缺失元数据保持 null。
 */
public interface OcrProvider {

    /**
     * 识别图片文字。
     * 参数 request 为已校验的图片字节、可信 MIME 类型、受控语言和识别模式；返回统一 Provider 结果。
     */
    OcrResult recognize(OcrRequest request);

    /**
     * 检查 Provider 是否具备运行条件。
     * 返回值只表示本地 OCR 引擎是否可调用，不触发用户图片识别。
     */
    boolean isAvailable();

    /**
     * 返回引擎名称。
     */
    String engineName();

    /**
     * 返回 Provider 名称。
     */
    String providerName();
}
