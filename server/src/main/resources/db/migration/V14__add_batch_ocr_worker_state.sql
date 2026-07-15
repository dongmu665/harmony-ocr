-- V1.2 批量 OCR Worker 状态迁移：增加重试、锁定和取消等后台执行字段。
-- 维护边界：锁定字段只用于任务调度，不表示用户授权；每次处理仍必须按 user_id 校验归属。
ALTER TABLE batch_ocr_jobs
    ADD COLUMN status VARCHAR(32) NOT NULL DEFAULT 'QUEUED';

ALTER TABLE batch_ocr_jobs
    ADD COLUMN progress INT NOT NULL DEFAULT 0;

ALTER TABLE batch_ocr_items
    ADD COLUMN retry_count INT NOT NULL DEFAULT 0;
