package com.harmonyocr.storage;

import java.io.InputStream;

/**
 * 对象存储服务抽象，属于 storage 模块。
 * 维护说明：文件业务只依赖该接口，开发环境可接 MinIO，测试环境可接内存实现，从而避免自动化测试依赖 Docker 或真实对象存储。
 */
public interface ObjectStorageService {

    /**
     * 写入对象存储。
     * 参数包含服务端生成的 objectKey、文件流、文件大小和内容类型；返回写入后的对象元数据。
     * 可能抛出运行时异常表示底层存储失败。安全注意：实现不得记录文件内容或对象存储访问密钥。
     */
    StoredObject putObject(String objectKey, InputStream inputStream, long size, String contentType);

    /**
     * 删除对象存储中的对象。
     * 参数为服务端已保存的 objectKey；方法无返回值。安全注意：删除失败应由业务层脱敏处理，不应把密钥或签名信息暴露给客户端。
     */
    void deleteObject(String objectKey);
}
