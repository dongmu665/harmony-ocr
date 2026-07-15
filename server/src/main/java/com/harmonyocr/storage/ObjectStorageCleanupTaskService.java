package com.harmonyocr.storage;

import java.time.LocalDateTime;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;

/**
 * 对象存储待清理任务服务，属于 storage 模块。
 * 维护说明：当上传对象已成功但数据库元数据保存失败，且补偿删除也失败时，使用独立事务记录安全的待清理线索。
 */
@Service
public class ObjectStorageCleanupTaskService {

    private static final int MAX_REASON_LENGTH = 255;

    private final ObjectStorageCleanupTaskMapper cleanupTaskMapper;

    public ObjectStorageCleanupTaskService(ObjectStorageCleanupTaskMapper cleanupTaskMapper) {
        this.cleanupTaskMapper = cleanupTaskMapper;
    }

    /**
     * 记录待删除的孤儿对象。
     * 参数为 bucket、objectKey 和脱敏原因；返回值为空。安全注意：reason 只能写入异常类型或业务阶段，不得包含密钥、Token 或文件内容。
     */
    @Transactional(propagation = Propagation.REQUIRES_NEW)
    public void recordPendingDelete(String bucketName, String objectKey, String reason) {
        LocalDateTime now = LocalDateTime.now();
        ObjectStorageCleanupTaskEntity task = new ObjectStorageCleanupTaskEntity();
        task.setBucketName(bucketName);
        task.setObjectKey(objectKey);
        task.setReason(truncate(reason, MAX_REASON_LENGTH));
        task.setStatus("PENDING");
        task.setAttempts(0);
        task.setCreatedAt(now);
        task.setUpdatedAt(now);
        cleanupTaskMapper.insert(task);
    }

    private String truncate(String value, int maxLength) {
        if (value == null) {
            return "";
        }
        return value.length() <= maxLength ? value : value.substring(0, maxLength);
    }
}
