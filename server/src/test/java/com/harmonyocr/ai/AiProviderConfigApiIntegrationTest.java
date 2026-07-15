package com.harmonyocr.ai;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.sun.net.httpserver.HttpServer;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.net.InetSocketAddress;
import java.nio.charset.StandardCharsets;
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
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.patch;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * AI Provider 配置 API 集成测试，属于 ai 模块。
 * 维护说明：测试只使用运行时生成的占位 key，验证不明文持久化、归属隔离和 mock 测试连接，不调用真实第三方服务。
 */
@ActiveProfiles("test")
@AutoConfigureMockMvc
@SpringBootTest
@TestPropertySource(properties = "app.ai.byok.encryption-secret=test-only-byok-encryption-secret-32-bytes")
class AiProviderConfigApiIntegrationTest {

    @Autowired
    private MockMvc mockMvc;

    @Autowired
    private ObjectMapper objectMapper;

    @Autowired
    private JdbcTemplate jdbcTemplate;

    @BeforeEach
    void cleanDatabase() {
        jdbcTemplate.update("DELETE FROM ai_provider_configs");
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
    void createReplaceTestAndDeleteProviderWithoutPlaintextKeyPersistence() throws Exception {
        String password = testPassword();
        register("alice", password);
        String token = bearer(accessToken("alice", password));
        String firstKey = runtimeApiKey();
        String secondKey = runtimeApiKey();

        MvcResult created = mockMvc.perform(post("/api/v1/ai/providers")
                        .header(HttpHeaders.AUTHORIZATION, token)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(json(Map.of(
                                "providerName", "Alice OpenAI Compatible",
                                "baseUrl", "https://provider.example/v1",
                                "modelName", "gpt-compatible",
                                "apiKey", firstKey,
                                "enabled", true,
                                "defaultProvider", true))))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.providerName").value("Alice OpenAI Compatible"))
                .andExpect(jsonPath("$.data.apiKeyConfigured").value(true))
                .andExpect(jsonPath("$.data.apiKeyMasked").value(maskedKey(firstKey)))
                .andExpect(jsonPath("$.data.secureStorageStatus").value("ENCRYPTED_AES_GCM"))
                .andExpect(jsonPath("$.data", not(hasKey("apiKey"))))
                .andReturn();

        Long providerId = jsonNode(created).path("data").path("id").asLong();
        assertPersistedProviderDoesNotContain(providerId, firstKey);
        assertEncryptedKeyStored(providerId);

        mockMvc.perform(post("/api/v1/ai/providers/{id}/test", providerId)
                        .header(HttpHeaders.AUTHORIZATION, token))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.status").value("REAL_FAILED"))
                .andExpect(jsonPath("$.data.degraded").value(true))
                .andExpect(jsonPath("$.data.providerName").value("Alice OpenAI Compatible"));

        MvcResult replaced = mockMvc.perform(patch("/api/v1/ai/providers/{id}", providerId)
                        .header(HttpHeaders.AUTHORIZATION, token)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(json(Map.of(
                                "apiKey", secondKey,
                                "enabled", false,
                                "defaultProvider", false))))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.enabled").value(false))
                .andExpect(jsonPath("$.data.defaultProvider").value(false))
                .andExpect(jsonPath("$.data.apiKeyMasked").value(maskedKey(secondKey)))
                .andReturn();

        assertThat(jsonNode(replaced).path("data").path("apiKeyFingerprint").asText())
                .isNotEqualTo(jsonNode(created).path("data").path("apiKeyFingerprint").asText());
        assertPersistedProviderDoesNotContain(providerId, firstKey);
        assertPersistedProviderDoesNotContain(providerId, secondKey);
        assertEncryptedKeyStored(providerId);

        mockMvc.perform(get("/api/v1/ai/providers")
                        .header(HttpHeaders.AUTHORIZATION, token))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data[0].id").value(providerId));

        mockMvc.perform(delete("/api/v1/ai/providers/{id}", providerId)
                        .header(HttpHeaders.AUTHORIZATION, token))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.code").value("OK"));

        assertThat(jdbcTemplate.queryForObject(
                "SELECT deleted FROM ai_provider_configs WHERE id = ?",
                Boolean.class,
                providerId)).isTrue();
    }

    @Test
    void encryptedProviderKeyCanCallLoopbackCompatibleApiOnlyInMemory() throws Exception {
        HttpServer server = HttpServer.create(new InetSocketAddress("127.0.0.1", 0), 0);
        String expectedKey = runtimeApiKey();
        server.createContext("/v1/chat/completions", exchange -> {
            String authorization = exchange.getRequestHeaders().getFirst(HttpHeaders.AUTHORIZATION);
            String response;
            int status;
            if (("Bearer " + expectedKey).equals(authorization)) {
                status = 200;
                response = "{\"choices\":[{\"message\":{\"content\":\"provider-ok\"}}]}";
            } else {
                status = 401;
                response = "{\"error\":\"unauthorized\"}";
            }
            byte[] body = response.getBytes(StandardCharsets.UTF_8);
            exchange.getResponseHeaders().set("Content-Type", "application/json");
            exchange.sendResponseHeaders(status, body.length);
            exchange.getResponseBody().write(body);
            exchange.close();
        });
        server.start();
        try {
            String password = testPassword();
            register("alice", password);
            String token = bearer(accessToken("alice", password));
            MvcResult created = mockMvc.perform(post("/api/v1/ai/providers")
                            .header(HttpHeaders.AUTHORIZATION, token)
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(json(Map.of(
                                    "providerName", "Loopback Provider",
                                    "baseUrl", "http://127.0.0.1:" + server.getAddress().getPort() + "/v1",
                                    "modelName", "local-compatible",
                                    "apiKey", expectedKey,
                                    "enabled", true))))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.data.secureStorageStatus").value("ENCRYPTED_AES_GCM"))
                    .andReturn();

            Long providerId = jsonNode(created).path("data").path("id").asLong();
            assertPersistedProviderDoesNotContain(providerId, expectedKey);

            mockMvc.perform(post("/api/v1/ai/providers/{id}/test", providerId)
                            .header(HttpHeaders.AUTHORIZATION, token))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.data.status").value("REAL_SUCCESS"))
                    .andExpect(jsonPath("$.data.degraded").value(false))
                    .andExpect(jsonPath("$.data.message").value("Provider connection succeeded"));
        } finally {
            server.stop(0);
        }
    }

    @Test
    void reencryptProviderKeyRotatesCiphertextWithoutChangingFingerprintOrReturningSecrets() throws Exception {
        String password = testPassword();
        register("alice", password);
        String token = bearer(accessToken("alice", password));
        String apiKey = runtimeApiKey();

        MvcResult created = mockMvc.perform(post("/api/v1/ai/providers")
                        .header(HttpHeaders.AUTHORIZATION, token)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(json(Map.of(
                                "providerName", "Rotation Provider",
                                "baseUrl", "https://provider.example/v1",
                                "modelName", "rotation-model",
                                "apiKey", apiKey,
                                "enabled", true))))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data", not(hasKey("apiKey"))))
                .andReturn();

        Long providerId = jsonNode(created).path("data").path("id").asLong();
        String originalFingerprint = jsonNode(created).path("data").path("apiKeyFingerprint").asText();
        String originalCiphertext = encryptedKey(providerId);

        MvcResult rotated = mockMvc.perform(post("/api/v1/ai/providers/{id}/reencrypt", providerId)
                        .header(HttpHeaders.AUTHORIZATION, token))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.id").value(providerId))
                .andExpect(jsonPath("$.data.apiKeyFingerprint").value(originalFingerprint))
                .andExpect(jsonPath("$.data.apiKeyConfigured").value(true))
                .andExpect(jsonPath("$.data.secureStorageStatus").value("ENCRYPTED_AES_GCM"))
                .andExpect(jsonPath("$.data", not(hasKey("apiKey"))))
                .andReturn();

        String rotatedCiphertext = encryptedKey(providerId);
        assertThat(rotatedCiphertext).isNotEqualTo(originalCiphertext);
        assertThat(jsonNode(rotated).path("data").path("apiKeyFingerprint").asText()).isEqualTo(originalFingerprint);
        assertPersistedProviderDoesNotContain(providerId, apiKey);
    }

    @Test
    void providerConfigIsOwnedByCurrentUser() throws Exception {
        String alicePassword = testPassword();
        String bobPassword = testPassword();
        register("alice", alicePassword);
        register("bob", bobPassword);
        String aliceToken = bearer(accessToken("alice", alicePassword));
        String bobToken = bearer(accessToken("bob", bobPassword));

        MvcResult created = mockMvc.perform(post("/api/v1/ai/providers")
                        .header(HttpHeaders.AUTHORIZATION, aliceToken)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(json(Map.of(
                                "providerName", "Alice Provider",
                                "baseUrl", "https://provider.example/v1",
                                "modelName", "contract-model",
                                "apiKey", runtimeApiKey(),
                                "enabled", true))))
                .andExpect(status().isOk())
                .andReturn();

        Long providerId = jsonNode(created).path("data").path("id").asLong();

        mockMvc.perform(post("/api/v1/ai/providers/{id}/test", providerId)
                        .header(HttpHeaders.AUTHORIZATION, bobToken))
                .andExpect(status().isNotFound())
                .andExpect(jsonPath("$.code").value("NOT_FOUND"));

        mockMvc.perform(get("/api/v1/ai/providers")
                        .header(HttpHeaders.AUTHORIZATION, bobToken))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data").isArray())
                .andExpect(jsonPath("$.data").isEmpty());
    }

    private void assertPersistedProviderDoesNotContain(Long providerId, String forbiddenValue) {
        List<String> values = jdbcTemplate.queryForList("""
                SELECT provider_name || '|' || base_url || '|' || model_name || '|' ||
                       api_key_fingerprint || '|' || encrypted_api_key || '|' || secure_storage_status
                FROM ai_provider_configs
                WHERE id = ?
                """, String.class, providerId);
        assertThat(values).hasSize(1);
        assertThat(values.get(0)).doesNotContain(forbiddenValue);
    }

    private void assertEncryptedKeyStored(Long providerId) {
        String encrypted = jdbcTemplate.queryForObject(
                "SELECT encrypted_api_key FROM ai_provider_configs WHERE id = ?",
                String.class,
                providerId);
        assertThat(encrypted).isNotBlank();
        assertThat(encrypted).startsWith("v1:");
    }

    private String encryptedKey(Long providerId) {
        return jdbcTemplate.queryForObject(
                "SELECT encrypted_api_key FROM ai_provider_configs WHERE id = ?",
                String.class,
                providerId);
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

    private String testPassword() {
        return "test-" + UUID.randomUUID();
    }

    private String runtimeApiKey() {
        return "runtime-placeholder-" + UUID.randomUUID();
    }

    private String maskedKey(String apiKey) {
        String trimmed = apiKey.trim();
        return "****" + trimmed.substring(trimmed.length() - 4);
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
