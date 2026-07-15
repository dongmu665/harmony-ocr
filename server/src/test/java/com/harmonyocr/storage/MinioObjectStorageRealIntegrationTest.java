package com.harmonyocr.storage;

import com.harmonyocr.config.MinioProperties;
import io.minio.MinioClient;
import io.minio.StatObjectArgs;
import io.minio.errors.ErrorResponseException;
import java.io.ByteArrayInputStream;
import java.nio.charset.StandardCharsets;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.condition.EnabledIfSystemProperty;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

/**
 * 真实 MinIO 集成验证，属于 storage 模块。
 * 维护说明：该测试默认关闭，只在本地集成验证时通过系统属性启用；测试对象使用独立命名空间，且清理范围只限本测试创建的对象。
 */
@EnabledIfSystemProperty(named = "harmonyocr.realMinio", matches = "true")
class MinioObjectStorageRealIntegrationTest {

    private static final String TEST_OBJECT_NAMESPACE = "integration-tests/minio-object-storage";

    @Test
    void putObjectAndDeleteObjectAgainstLocalMinioWithIsolatedTestObject() throws Exception {
        MinioProperties properties = minioPropertiesFromEnvironment();
        MinioObjectStorageService storageService = new MinioObjectStorageService(properties);
        MinioClient client = minioClient(properties);
        String objectKey = TEST_OBJECT_NAMESPACE + "/" + UUID.randomUUID() + ".txt";
        byte[] content = "object storage integration fixture".getBytes(StandardCharsets.UTF_8);
        boolean uploaded = false;

        try {
            StoredObject storedObject = storageService.putObject(
                    objectKey,
                    new ByteArrayInputStream(content),
                    content.length,
                    "text/plain");
            uploaded = true;

            assertThat(storedObject.objectKey()).isEqualTo(objectKey);
            assertThat(storedObject.size()).isEqualTo(content.length);
            assertThat(storedObject.contentType()).isEqualTo("text/plain");
            assertThat(objectKey).startsWith(TEST_OBJECT_NAMESPACE + "/");
            assertThat(statObject(client, properties, objectKey).size()).isEqualTo(content.length);
        } finally {
            if (uploaded) {
                storageService.deleteObject(objectKey);
            }
        }

        assertThatThrownBy(() -> statObject(client, properties, objectKey))
                .isInstanceOf(ErrorResponseException.class)
                .hasMessageContaining("Object does not exist");
    }

    /**
     * 从环境变量读取本地 MinIO 配置。
     * 安全注意：只校验变量是否存在，不输出访问密钥或 secret；调用方负责从本地 deploy/.env 注入变量。
     */
    private MinioProperties minioPropertiesFromEnvironment() {
        return new MinioProperties(
                envOrDefault("MINIO_ENDPOINT", localMinioEndpoint()),
                requiredAnyEnv("MINIO_ACCESS_KEY", "MINIO_ROOT_USER"),
                requiredAnyEnv("MINIO_SECRET_KEY", "MINIO_ROOT_PASSWORD"),
                envOrDefault("MINIO_BUCKET", "harmony-ocr"));
    }

    private MinioClient minioClient(MinioProperties properties) {
        return MinioClient.builder()
                .endpoint(properties.endpoint())
                .credentials(properties.accessKey(), properties.secretKey())
                .build();
    }

    private io.minio.StatObjectResponse statObject(
            MinioClient client,
            MinioProperties properties,
            String objectKey) throws Exception {
        return client.statObject(StatObjectArgs.builder()
                .bucket(properties.bucket())
                .object(objectKey)
                .build());
    }

    private String requiredEnv(String name) {
        String value = System.getenv(name);
        assertThat(value)
                .as(name + " must be set in the local test process")
                .isNotBlank();
        return value;
    }

    private String requiredAnyEnv(String primaryName, String fallbackName) {
        String primaryValue = System.getenv(primaryName);
        if (primaryValue != null && !primaryValue.isBlank()) {
            return primaryValue;
        }
        String fallbackValue = System.getenv(fallbackName);
        assertThat(fallbackValue)
                .as(primaryName + " or " + fallbackName + " must be set in the local test process")
                .isNotBlank();
        return fallbackValue;
    }

    private String envOrDefault(String name, String defaultValue) {
        String value = System.getenv(name);
        if (value == null || value.isBlank()) {
            return defaultValue;
        }
        return value;
    }

    private String localMinioEndpoint() {
        return "http://localhost:" + envOrDefault("MINIO_API_PORT", "9000");
    }
}
