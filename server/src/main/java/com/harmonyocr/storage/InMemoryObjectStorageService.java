package com.harmonyocr.storage;

import java.io.IOException;
import java.io.InputStream;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import org.springframework.context.annotation.Profile;
import org.springframework.stereotype.Service;

/**
 * 测试环境内存对象存储实现，属于 storage 模块。
 * 维护说明：仅用于 test profile，模拟上传和删除行为，确保 `mvn test` 不依赖真实 MinIO、Docker 或网络服务。
 */
@Service
@Profile("test")
public class InMemoryObjectStorageService implements ObjectStorageService {

    private final Map<String, byte[]> objects = new ConcurrentHashMap<>();

    /**
     * 将文件内容读入内存并按 objectKey 保存。
     * 参数含义与接口一致；返回保存后的对象元数据。若读取流失败则抛出运行时异常，测试中不记录文件内容。
     */
    @Override
    public StoredObject putObject(String objectKey, InputStream inputStream, long size, String contentType) {
        try {
            objects.put(objectKey, inputStream.readAllBytes());
            return new StoredObject(objectKey, size, contentType);
        } catch (IOException ex) {
            throw new IllegalStateException("Failed to read test storage object", ex);
        }
    }

    /**
     * 从内存映射中移除对象。
     * 参数为 objectKey；对象不存在时按幂等删除处理，不向调用方暴露内部状态。
     */
    @Override
    public void deleteObject(String objectKey) {
        objects.remove(objectKey);
    }
}
