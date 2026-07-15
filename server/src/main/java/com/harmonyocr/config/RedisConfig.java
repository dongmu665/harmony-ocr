package com.harmonyocr.config;

import org.springframework.context.annotation.Configuration;

/**
 * Redis 基础配置占位类，属于 config 模块。
 *
 * 维护说明：当前依赖 Spring Boot 自动配置连接 Redis；后续如增加序列化、缓存命名空间或连接策略，
 * 必须避免在代码中写入 Redis 密码、生产地址或其他环境密钥。
 */
@Configuration
public class RedisConfig {
}
