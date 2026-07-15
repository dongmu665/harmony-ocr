package com.harmonyocr.user.mapper;

import com.baomidou.mybatisplus.core.mapper.BaseMapper;
import com.harmonyocr.user.entity.UserEntity;
import org.apache.ibatis.annotations.Mapper;

/**
 * 用户数据访问接口，属于 user 模块。
 * 维护说明：调用方必须避免把 password_hash 映射到对外响应对象。
 */
@Mapper
public interface UserMapper extends BaseMapper<UserEntity> {
}
