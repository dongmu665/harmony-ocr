package com.harmonyocr;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.boot.context.properties.ConfigurationPropertiesScan;

/**
 * Harmony OCR 后端服务启动入口，属于 server 根模块。
 *
 * 维护说明：该类只负责装配 Spring Boot 应用和配置属性扫描，不承载业务逻辑、密钥或环境差异配置。
 */
@ConfigurationPropertiesScan
@SpringBootApplication
public class HarmonyOcrServerApplication {

    /**
     * 启动 Spring Boot 应用。
     *
     * @param args 命令行参数，由运行环境传入
     */
    public static void main(String[] args) {
        SpringApplication.run(HarmonyOcrServerApplication.class, args);
    }
}
