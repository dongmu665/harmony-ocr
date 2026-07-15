package com.harmonyocr.record.mapper;

import com.baomidou.mybatisplus.core.mapper.BaseMapper;
import com.harmonyocr.record.entity.RecognitionRecordPageBlockEntity;
import org.apache.ibatis.annotations.Mapper;

/**
 * PDF OCR 页级文本块数据访问接口，属于 record 模块。
 * 维护说明：仅由 RecordService 在父记录已确认归属后读写。
 */
@Mapper
public interface RecognitionRecordPageBlockMapper extends BaseMapper<RecognitionRecordPageBlockEntity> {
}
