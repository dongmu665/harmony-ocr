package com.harmonyocr.ocr.provider;

import org.springframework.core.io.ByteArrayResource;

/**
 * 带文件名的内存图片资源，属于 ocr provider 模块。
 * 维护说明：仅用于向外置 OCR 服务发送本次请求的图片字节，不把图片写入磁盘或长期日志。
 */
final class NamedByteArrayResource extends ByteArrayResource {

    private final String filename;

    NamedByteArrayResource(byte[] byteArray, String filename) {
        super(byteArray);
        this.filename = filename;
    }

    /**
     * 返回 multipart 文件名。
     * 返回值不包含用户原始文件名，避免向外置服务和日志传播本地路径或隐私命名。
     */
    @Override
    public String getFilename() {
        return filename;
    }
}
