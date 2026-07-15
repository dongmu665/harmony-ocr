package com.harmonyocr.record.mapper;

import com.baomidou.mybatisplus.core.mapper.BaseMapper;
import com.harmonyocr.record.entity.RecognitionBlockEntity;
import org.apache.ibatis.annotations.Mapper;

/**
 * OCR 文本块数据访问接口，属于 record 模块。
 * 维护说明：文本块访问必须先校验父记录归属，不能仅凭 block id 或 record id 直接对外返回。
 */
@Mapper
public interface RecognitionBlockMapper extends BaseMapper<RecognitionBlockEntity> {
}
