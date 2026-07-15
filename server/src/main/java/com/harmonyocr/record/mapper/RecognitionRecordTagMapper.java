package com.harmonyocr.record.mapper;

import com.baomidou.mybatisplus.core.mapper.BaseMapper;
import com.harmonyocr.record.entity.RecognitionRecordTagEntity;
import org.apache.ibatis.annotations.Mapper;

/**
 * OCR 历史记录标签绑定数据访问接口，属于 record 模块。
 * 维护说明：绑定写入必须先做 record/tag 双重归属校验，不能仅依赖外键。
 */
@Mapper
public interface RecognitionRecordTagMapper extends BaseMapper<RecognitionRecordTagEntity> {
}
