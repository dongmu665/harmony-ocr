-- 用户数据约束加固迁移：补充对象存储清理任务和 OCR 记录软删除字段。
-- 维护边界：清理任务只保存对象 key 和状态，不保存文件二进制、Token 或外部存储凭据。
CREATE TABLE object_storage_cleanup_tasks (
    id BIGINT NOT NULL AUTO_INCREMENT,
    bucket_name VARCHAR(128) NOT NULL,
    object_key VARCHAR(512) NOT NULL,
    reason VARCHAR(255) NOT NULL,
    status VARCHAR(32) NOT NULL DEFAULT 'PENDING',
    attempts INT NOT NULL DEFAULT 0,
    last_error VARCHAR(512) NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    KEY idx_cleanup_tasks_status_created (status, created_at),
    KEY idx_cleanup_tasks_bucket_object (bucket_name, object_key)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

UPDATE file_objects
SET bucket_name = 'harmony-ocr'
WHERE bucket_name IS NULL OR bucket_name = '';

ALTER TABLE file_objects
    MODIFY COLUMN bucket_name VARCHAR(128) NOT NULL;

ALTER TABLE file_objects
    ADD COLUMN storage_delete_status VARCHAR(32) NOT NULL DEFAULT 'ACTIVE';

ALTER TABLE file_objects
    ADD COLUMN storage_delete_attempts INT NOT NULL DEFAULT 0;

ALTER TABLE file_objects
    ADD COLUMN last_storage_delete_error VARCHAR(512) NULL;

ALTER TABLE file_objects
    ADD COLUMN last_storage_delete_attempt_at DATETIME NULL;

ALTER TABLE file_objects
    ADD COLUMN storage_deleted_at DATETIME NULL;

CREATE INDEX idx_file_objects_user_object_deleted
    ON file_objects (user_id, object_key, deleted);

CREATE INDEX idx_file_objects_storage_delete
    ON file_objects (storage_delete_status, last_storage_delete_attempt_at);

ALTER TABLE recognition_blocks
    ADD CONSTRAINT uk_recognition_blocks_record_index UNIQUE (record_id, block_index);
