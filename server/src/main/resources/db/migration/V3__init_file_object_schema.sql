-- V1.0 文件对象元数据表：保存对象存储 key、文件名、类型和大小。
-- 安全边界：MySQL 不保存文件二进制；所有文件访问必须由后端按 owner_user_id 校验。
CREATE TABLE file_objects (
    id BIGINT NOT NULL AUTO_INCREMENT,
    user_id BIGINT NOT NULL,
    object_key VARCHAR(512) NOT NULL,
    original_filename VARCHAR(255) NULL,
    content_type VARCHAR(128) NOT NULL,
    file_size BIGINT NOT NULL,
    file_hash VARCHAR(128) NULL,
    storage_provider VARCHAR(64) NOT NULL DEFAULT 'minio',
    bucket_name VARCHAR(128) NULL,
    deleted TINYINT NOT NULL DEFAULT 0,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    deleted_at DATETIME NULL,
    PRIMARY KEY (id),
    UNIQUE KEY uk_file_objects_bucket_object_key (bucket_name, object_key),
    KEY idx_file_objects_user_created (user_id, created_at),
    KEY idx_file_objects_hash (file_hash),
    KEY idx_file_objects_deleted (user_id, deleted),
    CONSTRAINT fk_file_objects_user
        FOREIGN KEY (user_id) REFERENCES users (id)
        ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
