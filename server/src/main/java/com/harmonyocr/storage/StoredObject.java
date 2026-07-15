package com.harmonyocr.storage;

/**
 * 对象存储写入结果，属于 storage 模块。
 * 维护说明：仅承载对象 key、大小和内容类型等非敏感元数据，不包含访问密钥、签名 URL 或文件二进制内容。
 */
public record StoredObject(
        String objectKey,
        long size,
        String contentType
) {
}
