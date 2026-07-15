package com.harmonyocr.record;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.util.Map;
import java.util.UUID;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.MvcResult;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.patch;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * RecordSyncSimulationIntegrationTest 负责在无真机条件下模拟同一账号的双客户端同步行为。
 * 所属模块：record 集成测试；维护说明：测试只使用本地 test profile 和运行时临时密码，不记录真实 Token 或生产凭据。
 */
@ActiveProfiles("test")
@AutoConfigureMockMvc
@SpringBootTest
class RecordSyncSimulationIntegrationTest {

    private static final String USERNAME = "sync_user";
    private static final String DEVICE_A = "sync-device-a";
    private static final String DEVICE_B = "sync-device-b";

    @Autowired
    private MockMvc mockMvc;

    @Autowired
    private ObjectMapper objectMapper;

    @Autowired
    private JdbcTemplate jdbcTemplate;

    private String password;

    @BeforeEach
    void cleanDatabase() {
        password = "Sync-" + UUID.randomUUID();
        jdbcTemplate.update("DELETE FROM object_storage_cleanup_tasks");
        jdbcTemplate.update("DELETE FROM file_objects");
        jdbcTemplate.update("DELETE FROM recognition_blocks");
        jdbcTemplate.update("DELETE FROM recognition_records");
        jdbcTemplate.update("DELETE FROM refresh_tokens");
        jdbcTemplate.update("DELETE FROM user_devices");
        jdbcTemplate.update("DELETE FROM export_jobs");
        jdbcTemplate.update("DELETE FROM batch_ocr_items");
        jdbcTemplate.update("DELETE FROM batch_ocr_jobs");
        jdbcTemplate.update("DELETE FROM users");
    }

    /**
     * 验证两个 deviceId 登录会话能观察同一份服务端记录状态。
     * 安全边界：断言同步可见性和 last-write-wins 现状，但不把它表述为完整冲突解决策略。
     */
    @Test
    void sameAccountTwoDeviceSessionsObserveServerAuthoritativeRecordChanges() throws Exception {
        register();
        String tokenA = login(DEVICE_A);
        String tokenB = login(DEVICE_B);

        Long userId = jdbcTemplate.queryForObject("SELECT id FROM users WHERE username = ?", Long.class, USERNAME);
        assertThat(jdbcTemplate.queryForObject(
                "SELECT COUNT(*) FROM user_devices WHERE user_id = ? AND device_id IN (?, ?)",
                Integer.class,
                userId,
                DEVICE_A,
                DEVICE_B)).isEqualTo(2);

        Long recordId = createRecord(tokenA);

        mockMvc.perform(get("/api/v1/records")
                        .header(HttpHeaders.AUTHORIZATION, bearer(tokenB)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.total").value(1))
                .andExpect(jsonPath("$.data.items[0].id").value(recordId));

        mockMvc.perform(get("/api/v1/records/{id}", recordId)
                        .header(HttpHeaders.AUTHORIZATION, bearer(tokenB)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.title").value("Client A source"));

        mockMvc.perform(patch("/api/v1/records/{id}", recordId)
                        .header(HttpHeaders.AUTHORIZATION, bearer(tokenB))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(json(Map.of(
                                "title", "Client B update",
                                "editedText", "client b edited text"))))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.title").value("Client B update"));

        mockMvc.perform(get("/api/v1/records/{id}", recordId)
                        .header(HttpHeaders.AUTHORIZATION, bearer(tokenA)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.editedText").value("client b edited text"));

        mockMvc.perform(post("/api/v1/records/{id}/favorite", recordId)
                        .header(HttpHeaders.AUTHORIZATION, bearer(tokenA))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(json(Map.of("favorite", true))))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.favorite").value(true));

        mockMvc.perform(get("/api/v1/records")
                        .header(HttpHeaders.AUTHORIZATION, bearer(tokenB))
                        .param("favorite", "true"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.total").value(1))
                .andExpect(jsonPath("$.data.items[0].favorite").value(true));

        mockMvc.perform(patch("/api/v1/records/{id}", recordId)
                        .header(HttpHeaders.AUTHORIZATION, bearer(tokenA))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(json(Map.of("editedText", "client a near concurrent version"))))
                .andExpect(status().isOk());

        mockMvc.perform(patch("/api/v1/records/{id}", recordId)
                        .header(HttpHeaders.AUTHORIZATION, bearer(tokenB))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(json(Map.of("editedText", "client b last write version"))))
                .andExpect(status().isOk());

        mockMvc.perform(get("/api/v1/records/{id}", recordId)
                        .header(HttpHeaders.AUTHORIZATION, bearer(tokenA)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.editedText").value("client b last write version"));

        mockMvc.perform(delete("/api/v1/records/{id}", recordId)
                        .header(HttpHeaders.AUTHORIZATION, bearer(tokenB)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.success").value(true));

        mockMvc.perform(get("/api/v1/records/{id}", recordId)
                        .header(HttpHeaders.AUTHORIZATION, bearer(tokenA)))
                .andExpect(status().isNotFound())
                .andExpect(jsonPath("$.code").value("NOT_FOUND"));

        mockMvc.perform(get("/api/v1/records")
                        .header(HttpHeaders.AUTHORIZATION, bearer(tokenA)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.total").value(0));
    }

    /**
     * 固化 V1.0 课程验收的同步冲突观察结论：同一账号近连续 PATCH 按请求到达顺序后写覆盖前写。
     * 安全边界：该测试只证明当前 server-authoritative last-write-wins 行为，不引入乐观锁或复杂合并策略。
     */
    @Test
    void nearConsecutivePatchSameRecordBySameUserKeepsLastWriteWithoutConflict() throws Exception {
        register();
        String tokenA = login(DEVICE_A);
        String tokenB = login(DEVICE_B);
        Long recordId = createRecord(tokenA);

        mockMvc.perform(patch("/api/v1/records/{id}", recordId)
                        .header(HttpHeaders.AUTHORIZATION, bearer(tokenA))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(json(Map.of(
                                "title", "Client A near write",
                                "editedText", "client a near write text"))))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.title").value("Client A near write"))
                .andExpect(jsonPath("$.data.editedText").value("client a near write text"));

        mockMvc.perform(patch("/api/v1/records/{id}", recordId)
                        .header(HttpHeaders.AUTHORIZATION, bearer(tokenB))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(json(Map.of(
                                "title", "Client B last write",
                                "editedText", "client b last write text"))))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.title").value("Client B last write"))
                .andExpect(jsonPath("$.data.editedText").value("client b last write text"));

        mockMvc.perform(get("/api/v1/records/{id}", recordId)
                        .header(HttpHeaders.AUTHORIZATION, bearer(tokenA)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.title").value("Client B last write"))
                .andExpect(jsonPath("$.data.editedText").value("client b last write text"));
    }

    private void register() throws Exception {
        mockMvc.perform(post("/api/v1/auth/register")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(json(Map.of("username", USERNAME, "password", password))))
                .andExpect(status().isOk());
    }

    private String login(String deviceId) throws Exception {
        MvcResult result = mockMvc.perform(post("/api/v1/auth/login")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(json(Map.of(
                                "username", USERNAME,
                                "password", password,
                                "deviceId", deviceId,
                                "deviceName", deviceId))))
                .andExpect(status().isOk())
                .andReturn();
        return jsonNode(result).path("data").path("accessToken").asText();
    }

    private Long createRecord(String accessToken) throws Exception {
        MvcResult result = mockMvc.perform(post("/api/v1/records")
                        .header(HttpHeaders.AUTHORIZATION, bearer(accessToken))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(json(Map.of(
                                "title", "Client A source",
                                "sourceType", "camera",
                                "rawText", "raw sync text",
                                "editedText", "client a text",
                                "language", "zh-CN",
                                "ocrEngine", "sync-simulation",
                                "durationMs", 88))))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.id").isNumber())
                .andReturn();
        return jsonNode(result).path("data").path("id").asLong();
    }

    private String bearer(String accessToken) {
        return "Bearer " + accessToken;
    }

    private String json(Object value) throws Exception {
        return objectMapper.writeValueAsString(value);
    }

    private JsonNode jsonNode(MvcResult result) throws Exception {
        return objectMapper.readTree(result.getResponse().getContentAsString());
    }
}
