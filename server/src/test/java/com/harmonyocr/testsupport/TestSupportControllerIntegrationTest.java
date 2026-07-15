package com.harmonyocr.testsupport;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.util.Map;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.MvcResult;

import static org.hamcrest.Matchers.not;
import static org.hamcrest.Matchers.hasKey;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.multipart;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * 测试辅助接口集成测试，属于 testsupport 模块。
 * 维护说明：只验证 test profile 下的管理员 seed 能力，不输出或断言真实 Token、密码、API Key。
 */
@ActiveProfiles("test")
@AutoConfigureMockMvc
@SpringBootTest
class TestSupportControllerIntegrationTest {

    @Autowired
    private MockMvc mockMvc;

    @Autowired
    private ObjectMapper objectMapper;

    @Test
    void testProfileCanSeedCourseUserWithoutReturningPasswordMaterial() throws Exception {
        String username = "course_" + UUID.randomUUID().toString().replace("-", "").substring(0, 10);
        String shortPassword = "p" + UUID.randomUUID().toString().replace("-", "").substring(0, 5);

        mockMvc.perform(post("/api/v1/auth/register")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(json(Map.of("username", username, "password", shortPassword))))
                .andExpect(status().isBadRequest());

        mockMvc.perform(post("/api/v1/test-support/users")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(json(Map.of("username", username, "password", shortPassword))))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.username").value(username))
                .andExpect(jsonPath("$.data", not(hasKey("password"))))
                .andExpect(jsonPath("$.data", not(hasKey("passwordHash"))))
                .andExpect(jsonPath("$.data", not(hasKey("token"))));

        String token = accessToken(username, shortPassword);
        mockMvc.perform(get("/api/v1/users/me")
                        .header(HttpHeaders.AUTHORIZATION, bearer(token)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.username").value(username));
    }

    @Test
    void testProfileCanReseedExistingCourseUserPasswordWithoutSensitivePayloads() throws Exception {
        String username = "course_" + UUID.randomUUID().toString().replace("-", "").substring(0, 10);
        String firstPassword = "p" + UUID.randomUUID().toString().replace("-", "").substring(0, 5);
        String secondPassword = "p" + UUID.randomUUID().toString().replace("-", "").substring(0, 5);

        mockMvc.perform(post("/api/v1/test-support/users")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(json(Map.of("username", username, "password", firstPassword))))
                .andExpect(status().isOk());

        mockMvc.perform(post("/api/v1/test-support/users")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(json(Map.of("username", username, "password", secondPassword))))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.username").value(username))
                .andExpect(jsonPath("$.data", not(hasKey("password"))))
                .andExpect(jsonPath("$.data", not(hasKey("passwordHash"))))
                .andExpect(jsonPath("$.data", not(hasKey("token"))));

        mockMvc.perform(post("/api/v1/auth/login")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(json(Map.of("username", username, "password", firstPassword))))
                .andExpect(status().isUnauthorized());

        mockMvc.perform(get("/api/v1/users/me")
                        .header(HttpHeaders.AUTHORIZATION, bearer(accessToken(username, secondPassword))))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.username").value(username));
    }

    @Test
    void authenticatedTestUserCanSeedAdminRoleForLiveApiVerification() throws Exception {
        String username = "support_" + UUID.randomUUID().toString().replace("-", "").substring(0, 10);
        String password = "Ts!" + UUID.randomUUID().toString().replace("-", "");

        mockMvc.perform(post("/api/v1/auth/register")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(json(Map.of("username", username, "password", password))))
                .andExpect(status().isOk());
        String token = accessToken(username, password);

        mockMvc.perform(get("/api/v1/admin/users")
                        .header(HttpHeaders.AUTHORIZATION, bearer(token)))
                .andExpect(status().isForbidden());

        mockMvc.perform(post("/api/v1/test-support/admin/me")
                        .header(HttpHeaders.AUTHORIZATION, bearer(token)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.role").value("SUPER_ADMIN"))
                .andExpect(jsonPath("$.data", not(hasKey("password"))))
                .andExpect(jsonPath("$.data", not(hasKey("token"))))
                .andExpect(jsonPath("$.data", not(hasKey("apiKey"))));

        mockMvc.perform(get("/api/v1/admin/users")
                        .header(HttpHeaders.AUTHORIZATION, bearer(token)))
                .andExpect(status().isOk());

        mockMvc.perform(get("/api/v1/test-support/ai/byok-status")
                        .header(HttpHeaders.AUTHORIZATION, bearer(token)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.configured").isBoolean())
                .andExpect(jsonPath("$.data", not(hasKey("secret"))))
                .andExpect(jsonPath("$.data", not(hasKey("apiKey"))));
    }

    /**
     * 登录测试账号。
     * 参数为临时用户名和密码；返回值只在内存中作为 Authorization Header 使用，不写入日志或持久化证据。
     */
    @Test
    void authenticatedTestUserCanSeedDashboardDataWithoutSensitivePayloads() throws Exception {
        String username = "dash_" + UUID.randomUUID().toString().replace("-", "").substring(0, 10);
        String password = "Ts!" + UUID.randomUUID().toString().replace("-", "");

        mockMvc.perform(post("/api/v1/auth/register")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(json(Map.of("username", username, "password", password))))
                .andExpect(status().isOk());
        String token = accessToken(username, password);

        mockMvc.perform(post("/api/v1/test-support/dashboard-data/me")
                        .header(HttpHeaders.AUTHORIZATION, bearer(token)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.recordCount").value(2))
                .andExpect(jsonPath("$.data.batchJobCount").value(1))
                .andExpect(jsonPath("$.data.exportJobCount").value(2))
                .andExpect(jsonPath("$.data", not(hasKey("password"))))
                .andExpect(jsonPath("$.data", not(hasKey("token"))))
                .andExpect(jsonPath("$.data", not(hasKey("apiKey"))))
                .andExpect(jsonPath("$.data", not(hasKey("objectKey"))))
                .andExpect(jsonPath("$.data", not(hasKey("rawText"))));

        mockMvc.perform(get("/api/v1/records?size=4")
                        .header(HttpHeaders.AUTHORIZATION, bearer(token)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.total").value(2))
                .andExpect(jsonPath("$.data.items[0].title").exists());

        mockMvc.perform(get("/api/v1/ocr/batches")
                        .header(HttpHeaders.AUTHORIZATION, bearer(token)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data[0].total").value(2))
                .andExpect(jsonPath("$.data[0].progress").value(50));

        mockMvc.perform(get("/api/v1/exports")
                        .header(HttpHeaders.AUTHORIZATION, bearer(token)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data[0].checksumSha256").isNotEmpty())
                .andExpect(jsonPath("$.data[0]", not(hasKey("content"))));
    }

    @Test
    void authenticatedTestUserCanExhaustQuotaForEmulatorVerificationWithoutSensitivePayloads() throws Exception {
        String username = "quota_" + UUID.randomUUID().toString().replace("-", "").substring(0, 10);
        String password = "Ts!" + UUID.randomUUID().toString().replace("-", "");

        mockMvc.perform(post("/api/v1/auth/register")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(json(Map.of("username", username, "password", password))))
                .andExpect(status().isOk());
        String token = accessToken(username, password);

        mockMvc.perform(post("/api/v1/test-support/quota/me/exhaust")
                        .header(HttpHeaders.AUTHORIZATION, bearer(token))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(json(Map.of("resourceType", "OCR"))))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.resourceType").value("OCR"))
                .andExpect(jsonPath("$.data.usedCount").value(0))
                .andExpect(jsonPath("$.data.quota").value(0))
                .andExpect(jsonPath("$.data", not(hasKey("password"))))
                .andExpect(jsonPath("$.data", not(hasKey("token"))))
                .andExpect(jsonPath("$.data", not(hasKey("apiKey"))))
                .andExpect(jsonPath("$.data", not(hasKey("rawText"))));

        mockMvc.perform(multipart("/api/v1/ocr/recognize")
                        .file("file", tinyPng())
                        .header(HttpHeaders.AUTHORIZATION, bearer(token)))
                .andExpect(status().isTooManyRequests())
                .andExpect(jsonPath("$.code").value("QUOTA_EXCEEDED"));
    }

    private String accessToken(String username, String password) throws Exception {
        MvcResult result = mockMvc.perform(post("/api/v1/auth/login")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(json(Map.of("username", username, "password", password))))
                .andExpect(status().isOk())
                .andReturn();
        return objectMapper.readTree(result.getResponse().getContentAsString()).path("data").path("accessToken").asText();
    }

    private String bearer(String accessToken) {
        return "Bearer " + accessToken;
    }

    private String json(Object value) throws Exception {
        return objectMapper.writeValueAsString(value);
    }

    private byte[] tinyPng() {
        return java.util.Base64.getDecoder().decode(
                "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII=");
    }
}
