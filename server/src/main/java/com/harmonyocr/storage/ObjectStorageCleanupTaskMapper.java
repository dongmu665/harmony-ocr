package com.harmonyocr.storage;

import com.baomidou.mybatisplus.core.mapper.BaseMapper;
import org.apache.ibatis.annotations.Mapper;

/**
 * 对象存储待清理任务 Mapper，属于 storage 模块。
 * 维护说明：仅保存可用于后续清理的 bucket 和 objectKey，不保存对象存储访问密钥或文件内容。
 */
@Mapper
public interface ObjectStorageCleanupTaskMapper extends BaseMapper<ObjectStorageCleanupTaskEntity> {
}
