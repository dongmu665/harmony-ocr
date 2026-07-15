package com.harmonyocr.record.entity;

import com.baomidou.mybatisplus.annotation.IdType;
import com.baomidou.mybatisplus.annotation.TableId;
import com.baomidou.mybatisplus.annotation.TableName;
import java.time.LocalDateTime;

/**
 * OCR 历史记录与标签绑定实体，属于 record 模块。
 * 维护说明：绑定表冗余 userId 便于查询和清理，写入前仍必须校验 record 和 tag 均属于当前用户。
 */
@TableName("recognition_record_tags")
public class RecognitionRecordTagEntity {

    @TableId(type = IdType.AUTO)
    private Long id;
    private Long userId;
    private Long recordId;
    private Long tagId;
    private LocalDateTime createdAt;

    public Long getId() {
        return id;
    }

    public void setId(Long id) {
        this.id = id;
    }

    public Long getUserId() {
        return userId;
    }

    public void setUserId(Long userId) {
        this.userId = userId;
    }

    public Long getRecordId() {
        return recordId;
    }

    public void setRecordId(Long recordId) {
        this.recordId = recordId;
    }

    public Long getTagId() {
        return tagId;
    }

    public void setTagId(Long tagId) {
        this.tagId = tagId;
    }

    public LocalDateTime getCreatedAt() {
        return createdAt;
    }

    public void setCreatedAt(LocalDateTime createdAt) {
        this.createdAt = createdAt;
    }
}
