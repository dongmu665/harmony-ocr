package com.harmonyocr.ai;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.sun.net.httpserver.HttpServer;
import java.net.InetSocketAddress;
import java.nio.charset.StandardCharsets;
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
import org.springframework.test.context.TestPropertySource;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.MvcResult;

import static org.assertj.core.api.Assertions.assertThat;
import static org.hamcrest.Matchers.not;
import static org.hamcrest.Matchers.hasKey;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * BYOK AI 动作集成测试，属于 ai 模块。
 * 维护说明：测试只使用运行时生成的占位 key 和本机 loopback 服务，验证加密保存的 key 可在内存解密后驱动 AI 动作。
 */
@ActiveProfiles("test")
@AutoConfigureMockMvc
@SpringBootTest
@TestPropertySource(properties = {
        "app.ai.provider=mock",
        "app.ai.byok.encryption-secret=test-only-byok-encryption-secret-32-bytes"
})
class AiByokActionIntegrationTest {

    @Autowired
    private MockMvc mockMvc;

    @Autowired
    private ObjectMapper objectMapper;

    @Autowired
    private JdbcTemplate jdbcTemplate;

    @BeforeEach
    void cleanDatabase() {
        jdbcTemplate.update("DELETE FROM ai_runtime_consents");
        jdbcTemplate.update("DELETE FROM ai_provider_configs");
        jdbcTemplate.update("DELETE FROM usage_counters");
        jdbcTemplate.update("DELETE FROM user_memberships");
        jdbcTemplate.update("DELETE FROM object_storage_cleanup_tasks");
        jdbcTemplate.update("DELETE FROM file_objects");
        jdbcTemplate.update("DELETE FROM recognition_record_tags");
        jdbcTemplate.update("DELETE FROM recognition_tags");
        jdbcTemplate.update("DELETE FROM recognition_blocks");
        jdbcTemplate.update("DELETE FROM recognition_records");
        jdbcTemplate.update("DELETE FROM refresh_tokens");
        jdbcTemplate.update("DELETE FROM user_devices");
        jdbcTemplate.update("DELETE FROM export_jobs");
        jdbcTemplate.update("DELETE FROM batch_ocr_items");
        jdbcTemplate.update("DELETE FROM batch_ocr_jobs");
        jdbcTemplate.update("DELETE FROM users");
    }

    @Test
    void aiActionUsesDefaultEncryptedByokProviderKeyInMemory() throws Exception {
        HttpServer server = HttpServer.create(new InetSocketAddress("127.0.0.1", 0), 0);
        String expectedKey = runtimeApiKey();
        server.createContext("/v1/chat/completions", exchange -> {
            String authorization = exchange.getRequestHeaders().getFirst(HttpHeaders.AUTHORIZATION);
            String bodyText = new String(exchange.getRequestBody().readAllBytes(), StandardCharsets.UTF_8);
            boolean accepted = ("Bearer " + expectedKey).equals(authorization)
                    && bodyText.contains("edited byok source text");
            String response = accepted
                    ? "{\"choices\":[{\"message\":{\"content\":\"byok-summary-ok\"}}]}"
                    : "{\"error\":\"unauthorized\"}";
            byte[] body = response.getBytes(StandardCharsets.UTF_8);
            exchange.getResponseHeaders().set("Content-Type", "application/json");
            exchange.sendResponseHeaders(accepted ? 200 : 401, body.length);
            exchange.getResponseBody().write(body);
            exchange.close();
        });
        server.start();
        try {
            String password = testPassword();
            register("alice", password);
            Long userId = userId("alice");
            Long recordId = insertRecord(userId, "edited byok source text");
            String token = bearer(accessToken("alice", password));

            MvcResult provider = mockMvc.perform(post("/api/v1/ai/providers")
                            .header(HttpHeaders.AUTHORIZATION, token)
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(json(Map.of(
                                    "providerName", "Loopback BYOK",
                                    "baseUrl", "http://127.0.0.1:" + server.getAddress().getPort() + "/v1",
                                    "modelName", "byok-local-model",
                                    "apiKey", expectedKey,
                                    "enabled", true,
                                    "defaultProvider", true))))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.data", not(hasKey("apiKey"))))
                    .andReturn();

            Long providerId = jsonNode(provider).path("data").path("id").asLong();
            assertPersistedProviderDoesNotContain(providerId, expectedKey);
            acceptAiConsent(token);

            mockMvc.perform(post("/api/v1/ai/actions")
                            .header(HttpHeaders.AUTHORIZATION, token)
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(json(Map.of(
                                    "recordId", recordId,
                                    "action", "SUMMARY",
                                    "consentAccepted", true))))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.data.providerName").value("Loopback BYOK"))
                    .andExpect(jsonPath("$.data.modelName").value("byok-local-model"))
                    .andExpect(jsonPath("$.data.outputText").value("byok-summary-ok"))
                    .andExpect(jsonPath("$.data.degraded").value(false));
        } finally {
            server.stop(0);
        }
    }

    private Long insertRecord(Long userId, String editedText) {
        jdbcTemplate.update("""
                INSERT INTO recognition_records
                    (user_id, title, source_type, raw_text, edited_text, favorite, deleted, created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, 0, 0, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
                """, userId, "BYOK AI", "album", "raw byok source text", editedText);
        return jdbcTemplate.queryForObject("SELECT MAX(id) FROM recognition_records", Long.class);
    }

    private void assertPersistedProviderDoesNotContain(Long providerId, String forbiddenValue) {
        String value = jdbcTemplate.queryForObject("""
                SELECT provider_name || '|' || base_url || '|' || model_name || '|' ||
                       api_key_fingerprint || '|' || encrypted_api_key || '|' || secure_storage_status
                FROM ai_provider_configs
                WHERE id = ?
                """, String.class, providerId);
        assertThat(value).doesNotContain(forbiddenValue);
    }

    private void acceptAiConsent(String token) throws Exception {
        mockMvc.perform(post("/api/v1/ai/consent")
                        .header(HttpHeaders.AUTHORIZATION, token)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(json(Map.of("accepted", true))))
                .andExpect(status().isOk());
    }

    private void register(String username, String password) throws Exception {
        mockMvc.perform(post("/api/v1/auth/register")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(json(Map.of("username", username, "password", password))))
                .andExpect(status().isOk());
    }

    private String accessToken(String username, String password) throws Exception {
        MvcResult result = mockMvc.perform(post("/api/v1/auth/login")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(json(Map.of("username", username, "password", password))))
                .andExpect(status().isOk())
                .andReturn();
        return jsonNode(result).path("data").path("accessToken").asText();
    }

    private Long userId(String username) {
        return jdbcTemplate.queryForObject("SELECT id FROM users WHERE username = ?", Long.class, username);
    }

    private String testPassword() {
        return "test-" + UUID.randomUUID();
    }

    private String runtimeApiKey() {
        return "runtime-placeholder-" + UUID.randomUUID();
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
