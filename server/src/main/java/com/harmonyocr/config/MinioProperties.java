package com.harmonyocr.config;

import org.springframework.boot.context.properties.ConfigurationProperties;

/**
 * MinIO 对象存储配置，属于 config 模块。
 * 维护说明：只绑定连接端点、访问凭据和 bucket 名称；真实密钥必须来自环境变量或本地配置，不得写入代码或日志。
 */
@ConfigurationProperties(prefix = "minio")
public record MinioProperties(
        String endpoint,
        String accessKey,
        String secretKey,
        String bucket
) {
}
