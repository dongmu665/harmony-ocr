package com.harmonyocr.record.mapper;

import com.baomidou.mybatisplus.core.mapper.BaseMapper;
import com.harmonyocr.record.entity.RecognitionRecordPageEntity;
import org.apache.ibatis.annotations.Mapper;

/**
 * PDF OCR 页级历史数据访问接口，属于 record 模块。
 * 维护说明：调用方必须先校验父记录归属，避免跨用户读取 OCR 页文本。
 */
@Mapper
public interface RecognitionRecordPageMapper extends BaseMapper<RecognitionRecordPageEntity> {
}
