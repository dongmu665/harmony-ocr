package com.harmonyocr.file.entity;

import com.baomidou.mybatisplus.annotation.IdType;
import com.baomidou.mybatisplus.annotation.TableId;
import com.baomidou.mybatisplus.annotation.TableName;
import java.time.LocalDateTime;

/**
 * 文件对象元数据实体，属于 file 模块。
 * 维护说明：仅保存对象存储 key、文件元数据和用户归属关系；文件二进制必须留在 MinIO 或测试存储中，不能进入 MySQL。
 */
@TableName("file_objects")
public class FileObjectEntity {

    @TableId(type = IdType.AUTO)
    private Long id;
    private Long userId;
    private String objectKey;
    private String originalFilename;
    private String contentType;
    private Long fileSize;
    private String fileHash;
    private String storageProvider;
    private String bucketName;
    private Boolean deleted;
    private LocalDateTime createdAt;
    private LocalDateTime deletedAt;
    private String storageDeleteStatus;
    private Integer storageDeleteAttempts;
    private String lastStorageDeleteError;
    private LocalDateTime lastStorageDeleteAttemptAt;
    private LocalDateTime storageDeletedAt;

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

    public String getObjectKey() {
        return objectKey;
    }

    public void setObjectKey(String objectKey) {
        this.objectKey = objectKey;
    }

    public String getOriginalFilename() {
        return originalFilename;
    }

    public void setOriginalFilename(String originalFilename) {
        this.originalFilename = originalFilename;
    }

    public String getContentType() {
        return contentType;
    }

    public void setContentType(String contentType) {
        this.contentType = contentType;
    }

    public Long getFileSize() {
        return fileSize;
    }

    public void setFileSize(Long fileSize) {
        this.fileSize = fileSize;
    }

    public String getFileHash() {
        return fileHash;
    }

    public void setFileHash(String fileHash) {
        this.fileHash = fileHash;
    }

    public String getStorageProvider() {
        return storageProvider;
    }

    public void setStorageProvider(String storageProvider) {
        this.storageProvider = storageProvider;
    }

    public String getBucketName() {
        return bucketName;
    }

    public void setBucketName(String bucketName) {
        this.bucketName = bucketName;
    }

    public Boolean getDeleted() {
        return deleted;
    }

    public void setDeleted(Boolean deleted) {
        this.deleted = deleted;
    }

    public LocalDateTime getCreatedAt() {
        return createdAt;
    }

    public void setCreatedAt(LocalDateTime createdAt) {
        this.createdAt = createdAt;
    }

    public LocalDateTime getDeletedAt() {
        return deletedAt;
    }

    public void setDeletedAt(LocalDateTime deletedAt) {
        this.deletedAt = deletedAt;
    }

    public String getStorageDeleteStatus() {
        return storageDeleteStatus;
    }

    public void setStorageDeleteStatus(String storageDeleteStatus) {
        this.storageDeleteStatus = storageDeleteStatus;
    }

    public Integer getStorageDeleteAttempts() {
        return storageDeleteAttempts;
    }

    public void setStorageDeleteAttempts(Integer storageDeleteAttempts) {
        this.storageDeleteAttempts = storageDeleteAttempts;
    }

    public String getLastStorageDeleteError() {
        return lastStorageDeleteError;
    }

    public void setLastStorageDeleteError(String lastStorageDeleteError) {
        this.lastStorageDeleteError = lastStorageDeleteError;
    }

    public LocalDateTime getLastStorageDeleteAttemptAt() {
        return lastStorageDeleteAttemptAt;
    }

    public void setLastStorageDeleteAttemptAt(LocalDateTime lastStorageDeleteAttemptAt) {
        this.lastStorageDeleteAttemptAt = lastStorageDeleteAttemptAt;
    }

    public LocalDateTime getStorageDeletedAt() {
        return storageDeletedAt;
    }

    public void setStorageDeletedAt(LocalDateTime storageDeletedAt) {
        this.storageDeletedAt = storageDeletedAt;
    }
}
