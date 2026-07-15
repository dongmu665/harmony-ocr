package com.harmonyocr;

import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.context.ActiveProfiles;

/**
 * Spring Boot 启动上下文测试。
 * 维护说明：验证 test profile 下应用上下文可以完整加载，防止配置、迁移或 Bean 装配问题阻断集成测试。
 */
@ActiveProfiles("test")
@SpringBootTest
class HarmonyOcrServerApplicationTests {

    @Test
    void contextLoads() {
    }
}
