package com.harmonyocr.file.mapper;

import com.baomidou.mybatisplus.core.mapper.BaseMapper;
import com.harmonyocr.file.entity.FileObjectEntity;
import org.apache.ibatis.annotations.Mapper;

/**
 * 文件对象元数据访问接口，属于 file 模块。
 * 维护说明：调用方必须在 service 层附加 userId 和 deleted 条件，避免跨用户读取或删除文件对象。
 */
@Mapper
public interface FileObjectMapper extends BaseMapper<FileObjectEntity> {
}
