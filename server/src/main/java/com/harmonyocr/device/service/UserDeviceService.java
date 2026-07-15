package com.harmonyocr.device.service;

import com.baomidou.mybatisplus.core.conditions.query.LambdaQueryWrapper;
import com.harmonyocr.device.entity.UserDeviceEntity;
import com.harmonyocr.device.mapper.UserDeviceMapper;
import java.time.LocalDateTime;
import org.springframework.stereotype.Service;
import org.springframework.util.StringUtils;

/**
 * 用户设备服务，属于 device 模块。
 * 维护说明：仅记录登录设备元数据，不保存设备密钥、Access Token 或 Refresh Token。
 */
@Service
public class UserDeviceService {

    private final UserDeviceMapper userDeviceMapper;

    public UserDeviceService(UserDeviceMapper userDeviceMapper) {
        this.userDeviceMapper = userDeviceMapper;
    }

    /**
     * 记录或更新用户登录设备。
     * 参数为用户 ID、设备 ID 和设备名称；deviceId 为空时不写入设备表。
     */
    public void recordLoginDevice(Long userId, String deviceId, String deviceName) {
        if (!StringUtils.hasText(deviceId)) {
            return;
        }
        UserDeviceEntity existing = userDeviceMapper.selectOne(new LambdaQueryWrapper<UserDeviceEntity>()
                .eq(UserDeviceEntity::getUserId, userId)
                .eq(UserDeviceEntity::getDeviceId, deviceId));
        if (existing == null) {
            UserDeviceEntity entity = new UserDeviceEntity();
            entity.setUserId(userId);
            entity.setDeviceId(deviceId);
            entity.setDeviceName(deviceName);
            entity.setLastActiveAt(LocalDateTime.now());
            entity.setCreatedAt(LocalDateTime.now());
            userDeviceMapper.insert(entity);
            return;
        }
        existing.setDeviceName(deviceName);
        existing.setLastActiveAt(LocalDateTime.now());
        userDeviceMapper.updateById(existing);
    }

    /**
     * 物理删除指定用户的设备信息。
     * 参数为账号注销流程确认的用户 ID；返回删除行数。安全注意：设备 ID、设备名称和系统版本可能关联个人设备，注销后不继续保留。
     */
    public int deleteByUserId(Long userId) {
        return userDeviceMapper.delete(new LambdaQueryWrapper<UserDeviceEntity>()
                .eq(UserDeviceEntity::getUserId, userId));
    }
}
