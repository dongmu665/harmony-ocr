package com.harmonyocr.auth.mapper;

import com.baomidou.mybatisplus.core.mapper.BaseMapper;
import com.harmonyocr.auth.entity.RefreshTokenEntity;
import org.apache.ibatis.annotations.Mapper;

/**
 * Refresh Token 数据访问接口，属于 auth 模块。
 * 维护说明：查询条件应使用 token_hash，避免明文 Refresh Token 进入数据库。
 */
@Mapper
public interface RefreshTokenMapper extends BaseMapper<RefreshTokenEntity> {
}
