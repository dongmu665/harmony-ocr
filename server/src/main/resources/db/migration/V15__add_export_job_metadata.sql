-- V1.2 导出任务元数据迁移：增加降级原因、校验和、搜索 PDF 标记和任务进度。
-- 安全边界：checksum 只用于文件完整性校验，不包含文件内容、Token 或对象存储访问凭据。
ALTER TABLE export_jobs
    ADD COLUMN progress INT NOT NULL DEFAULT 100;

ALTER TABLE export_jobs
    ADD COLUMN checksum_sha256 VARCHAR(64) NOT NULL DEFAULT '';

CREATE INDEX idx_export_jobs_checksum ON export_jobs(checksum_sha256);
