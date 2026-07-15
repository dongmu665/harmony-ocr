package com.harmonyocr.admin.controller;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import org.springframework.core.io.ClassPathResource;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.stereotype.Controller;
import org.springframework.util.StreamUtils;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.ResponseBody;

/**
 * 管理后台页面控制器，属于 admin 模块。
 * 维护说明：只暴露静态控制台入口，真实管理数据仍通过 JWT 保护的 admin API 获取。
 */
@Controller
public class AdminConsoleController {

    /**
     * 打开管理后台控制台页面。
     * 返回值为内置静态 HTML；页面本身不包含密钥、Token、密码或业务敏感数据。
     */
    @GetMapping("/admin/console")
    @ResponseBody
    public ResponseEntity<String> console() throws IOException {
        String body = StreamUtils.copyToString(
                new ClassPathResource("static/admin/console.html").getInputStream(),
                StandardCharsets.UTF_8);
        return ResponseEntity.ok()
                .contentType(new MediaType("text", "html", StandardCharsets.UTF_8))
                .body(body);
    }
}
