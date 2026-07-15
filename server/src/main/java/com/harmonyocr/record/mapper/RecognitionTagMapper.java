package com.harmonyocr.record.mapper;

import com.baomidou.mybatisplus.core.mapper.BaseMapper;
import com.harmonyocr.record.entity.RecognitionTagEntity;
import org.apache.ibatis.annotations.Mapper;

/**
 * OCR 历史标签数据访问接口，属于 record 模块。
 * 维护说明：调用方必须追加 userId 条件，避免跨用户读取或修改标签分类信息。
 */
@Mapper
public interface RecognitionTagMapper extends BaseMapper<RecognitionTagEntity> {
}
