package com.harmonyocr.storage;

import com.harmonyocr.config.MinioProperties;
import io.minio.BucketExistsArgs;
import io.minio.MakeBucketArgs;
import io.minio.MinioClient;
import io.minio.PutObjectArgs;
import io.minio.RemoveObjectArgs;
import java.io.InputStream;
import org.springframework.context.annotation.Profile;
import org.springframework.stereotype.Service;

/**
 * MinIO 对象存储实现，属于 storage 模块。
 * 维护说明：开发和非测试环境通过该实现写入对象存储；所有端点、bucket 和访问凭据均来自配置，不允许硬编码或输出到日志。
 */
@Service
@Profile("!test")
public class MinioObjectStorageService implements ObjectStorageService {

    private final MinioProperties properties;

    public MinioObjectStorageService(MinioProperties properties) {
        this.properties = properties;
    }

    /**
     * 上传对象到 MinIO，并在需要时创建 bucket。
     * 参数为服务端生成的 objectKey、输入流、大小和 MIME 类型；返回对象元数据。安全注意：异常信息由上层统一脱敏，不记录访问密钥。
     */
    @Override
    public StoredObject putObject(String objectKey, InputStream inputStream, long size, String contentType) {
        try {
            MinioClient client = minioClient();
            ensureBucket(client);
            client.putObject(PutObjectArgs.builder()
                    .bucket(properties.bucket())
                    .object(objectKey)
                    .stream(inputStream, size, -1)
                    .contentType(contentType)
                    .build());
            return new StoredObject(objectKey, size, contentType);
        } catch (Exception ex) {
            throw new IllegalStateException("Failed to upload object", ex);
        }
    }

    /**
     * 从 MinIO 删除指定 objectKey。
     * 参数为服务端保存的 objectKey；对象不存在或底层异常由 MinIO SDK 返回，上层会决定是否影响业务流程。
     */
    @Override
    public void deleteObject(String objectKey) {
        try {
            minioClient().removeObject(RemoveObjectArgs.builder()
                    .bucket(properties.bucket())
                    .object(objectKey)
                    .build());
        } catch (Exception ex) {
            throw new IllegalStateException("Failed to delete object", ex);
        }
    }

    private MinioClient minioClient() {
        return MinioClient.builder()
                .endpoint(properties.endpoint())
                .credentials(properties.accessKey(), properties.secretKey())
                .build();
    }

    private void ensureBucket(MinioClient client) throws Exception {
        boolean exists = client.bucketExists(BucketExistsArgs.builder()
                .bucket(properties.bucket())
                .build());
        if (!exists) {
            client.makeBucket(MakeBucketArgs.builder()
                    .bucket(properties.bucket())
                    .build());
        }
    }
}
