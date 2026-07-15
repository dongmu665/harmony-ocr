package com.harmonyocr.file.dto;

import java.time.LocalDateTime;

/**
 * 文件对象响应 DTO，属于 file 模块。
 * 维护说明：返回客户端可展示的文件元数据，不返回对象存储访问密钥、签名 URL 或文件二进制内容。
 */
public record FileObjectResponse(
        Long id,
        String objectKey,
        String fileName,
        String mimeType,
        Long size,
        String accessUrl,
        LocalDateTime expiresAt,
        String originalFilename,
        String contentType,
        Long fileSize,
        String fileHash,
        String storageProvider,
        LocalDateTime createdAt
) {
}
