package com.harmonyocr.file.entity;

/**
 * 文件对象存储删除状态枚举，属于 file 模块。
 * 维护说明：业务软删除由 file_objects.deleted 表示；本枚举只描述对象存储中文件本体的删除结果，便于后续补偿清理和审计。
 */
public enum StorageDeleteStatus {
    ACTIVE,
    DELETED,
    DELETE_FAILED
}
