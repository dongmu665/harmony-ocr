-- V1.2 批量 OCR 聚合历史记录关联。
-- 隐私边界：该字段只保存当前用户批量任务生成的历史记录 ID，不保存 OCR 全文、图片 URI、图片 bytes 或对象存储 key。
ALTER TABLE batch_ocr_jobs
    ADD COLUMN record_id BIGINT NULL;

CREATE INDEX idx_batch_ocr_jobs_record_id ON batch_ocr_jobs(record_id);
