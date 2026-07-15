package com.harmonyocr.device.mapper;

import com.baomidou.mybatisplus.core.mapper.BaseMapper;
import com.harmonyocr.device.entity.UserDeviceEntity;
import org.apache.ibatis.annotations.Mapper;

/**
 * 用户设备数据访问接口，属于 device 模块。
 * 维护说明：设备记录按 user_id 和 device_id 归属当前用户。
 */
@Mapper
public interface UserDeviceMapper extends BaseMapper<UserDeviceEntity> {
}
