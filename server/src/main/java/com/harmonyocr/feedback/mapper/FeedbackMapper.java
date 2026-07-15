package com.harmonyocr.feedback.mapper;

import com.baomidou.mybatisplus.core.mapper.BaseMapper;
import com.harmonyocr.feedback.entity.FeedbackEntity;
import org.apache.ibatis.annotations.Mapper;

/**
 * 用户反馈数据访问接口，属于 feedback 模块。
 * 维护说明：当前仅支持写入和账号注销清理，不能绕过 service 暴露后台查询或处理接口。
 */
@Mapper
public interface FeedbackMapper extends BaseMapper<FeedbackEntity> {
}
