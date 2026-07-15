package com.harmonyocr.ai.mapper;

import com.baomidou.mybatisplus.core.mapper.BaseMapper;
import com.harmonyocr.ai.entity.AiProviderConfigEntity;
import org.apache.ibatis.annotations.Mapper;

/**
 * AI Provider 配置数据访问接口，属于 ai 模块。
 * 维护说明：只能通过 service 层使用，避免绕过归属校验或把 API Key 设计成明文字段。
 */
@Mapper
public interface AiProviderConfigMapper extends BaseMapper<AiProviderConfigEntity> {
}
