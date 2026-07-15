package com.harmonyocr.record.mapper;

import com.baomidou.mybatisplus.core.mapper.BaseMapper;
import com.harmonyocr.record.entity.RecognitionRecordEntity;
import org.apache.ibatis.annotations.Mapper;

/**
 * OCR 历史记录数据访问接口，属于 record 模块。
 * 维护说明：调用方必须通过 service 统一追加 userId 和 deleted 条件，避免跨用户读取或修改 OCR 隐私文本。
 */
@Mapper
public interface RecognitionRecordMapper extends BaseMapper<RecognitionRecordEntity> {
}
