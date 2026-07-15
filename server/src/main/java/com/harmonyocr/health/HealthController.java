package com.harmonyocr.health;

import com.harmonyocr.common.api.Result;
import java.util.Map;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * 健康检查控制器，属于 health 模块。
 *
 * 维护说明：该接口允许匿名访问，只返回服务存活状态和服务名，不返回环境变量、版本密钥、数据库地址或依赖详情。
 */
@RestController
@RequestMapping("/api/v1/health")
public class HealthController {

    /**
     * 返回服务基础存活状态。
     *
     * @return 统一成功响应，data 中只包含脱敏健康元数据
     */
    @GetMapping
    public Result<Map<String, String>> health() {
        return Result.success(Map.of(
                "status", "UP",
                "service", "harmony-ocr-server"
        ));
    }
}
