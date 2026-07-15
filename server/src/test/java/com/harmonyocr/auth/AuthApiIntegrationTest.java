package com.harmonyocr.auth;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.util.Map;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.MediaType;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.MvcResult;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.content;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@ActiveProfiles("test")
@AutoConfigureMockMvc
@SpringBootTest
/**
 * 认证 API 集成测试。
 * 维护说明：覆盖注册、登录、刷新和退出登录的统一响应、安全错误码、密码哈希和 Refresh Token 轮换契约。
 */
class AuthApiIntegrationTest {

    @Autowired
    private MockMvc mockMvc;

    @Autowired
    private ObjectMapper objectMapper;

    @Autowired
    private JdbcTemplate jdbcTemplate;

    @Autowired
    private PasswordEncoder passwordEncoder;

    @BeforeEach
    void cleanDatabase() {
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

    @Test
    void registerReturnsUserProfileWithoutPasswordHash() throws Exception {
        mockMvc.perform(post("/api/v1/auth/register")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(json(Map.of(
                                "username", "alice",
                                "password", "password123",
                                "nickname", "Alice"))))
                .andExpect(status().isOk())
                .andExpect(content().contentTypeCompatibleWith(MediaType.APPLICATION_JSON))
                .andExpect(jsonPath("$.success").value(true))
                .andExpect(jsonPath("$.code").value("OK"))
                .andExpect(jsonPath("$.data.username").value("alice"))
                .andExpect(jsonPath("$.data.nickname").value("Alice"))
                .andExpect(jsonPath("$.data.passwordHash").doesNotExist());
    }

    @Test
    void registerRejectsDuplicateUsername() throws Exception {
        register("alice", "password123");

        mockMvc.perform(post("/api/v1/auth/register")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(json(Map.of("username", "alice", "password", "password123"))))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.success").value(false))
                .andExpect(jsonPath("$.code").value("USERNAME_ALREADY_EXISTS"));
    }

    @Test
    void registerRejectsPasswordShorterThanEightCharacters() throws Exception {
        mockMvc.perform(post("/api/v1/auth/register")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(json(Map.of("username", "alice", "password", "short"))))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.success").value(false))
                .andExpect(jsonPath("$.code").value("VALIDATION_ERROR"));
    }

    @Test
    void loginReturnsAccessTokenRefreshTokenBearerTypeExpiresInAndUser() throws Exception {
        register("alice", "password123");

        mockMvc.perform(post("/api/v1/auth/login")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(json(Map.of(
                                "username", "alice",
                                "password", "password123",
                                "deviceId", "device-1",
                                "deviceName", "test device"))))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.success").value(true))
                .andExpect(jsonPath("$.data.accessToken").isNotEmpty())
                .andExpect(jsonPath("$.data.refreshToken").isNotEmpty())
                .andExpect(jsonPath("$.data.tokenType").value("Bearer"))
                .andExpect(jsonPath("$.data.expiresIn").isNumber())
                .andExpect(jsonPath("$.data.user.username").value("alice"));
    }

    @Test
    void loginRejectsWrongPasswordWithInvalidCredentials() throws Exception {
        register("alice", "password123");

        mockMvc.perform(post("/api/v1/auth/login")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(json(Map.of("username", "alice", "password", "wrongpass"))))
                .andExpect(status().isUnauthorized())
                .andExpect(jsonPath("$.success").value(false))
                .andExpect(jsonPath("$.code").value("AUTH_INVALID_CREDENTIALS"));
    }

    @Test
    void loginRejectsMissingUserWithSameInvalidCredentialsResponseAsWrongPassword() throws Exception {
        MvcResult missingUser = mockMvc.perform(post("/api/v1/auth/login")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(json(Map.of("username", "missing", "password", "password123"))))
                .andExpect(status().isUnauthorized())
                .andExpect(jsonPath("$.code").value("AUTH_INVALID_CREDENTIALS"))
                .andReturn();

        register("alice", "password123");
        MvcResult wrongPassword = mockMvc.perform(post("/api/v1/auth/login")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(json(Map.of("username", "alice", "password", "wrongpass"))))
                .andExpect(status().isUnauthorized())
                .andExpect(jsonPath("$.code").value("AUTH_INVALID_CREDENTIALS"))
                .andReturn();

        assertThat(jsonNode(missingUser).path("message").asText())
                .isEqualTo(jsonNode(wrongPassword).path("message").asText());
    }

    @Test
    void registerStoresPasswordHashInsteadOfPlainPassword() throws Exception {
        register("alice", "password123");

        String passwordHash = jdbcTemplate.queryForObject(
                "SELECT password_hash FROM users WHERE username = ?",
                String.class,
                "alice");

        assertThat(passwordHash).isNotEqualTo("password123");
        assertThat(passwordEncoder.matches("password123", passwordHash)).isTrue();
    }

    @Test
    void loginStoresRefreshTokenHashInsteadOfPlainRefreshToken() throws Exception {
        register("alice", "password123");

        String refreshToken = login("alice", "password123").path("data").path("refreshToken").asText();
        String tokenHash = jdbcTemplate.queryForObject(
                "SELECT token_hash FROM refresh_tokens",
                String.class);

        assertThat(tokenHash).isNotEqualTo(refreshToken);
        assertThat(tokenHash).hasSize(64);
    }

    @Test
    void refreshWithValidRefreshTokenReturnsNewAccessTokenAndRotatesRefreshToken() throws Exception {
        register("alice", "password123");
        JsonNode login = login("alice", "password123");
        String oldRefreshToken = login.path("data").path("refreshToken").asText();

        MvcResult refreshResult = mockMvc.perform(post("/api/v1/auth/refresh")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(json(Map.of("refreshToken", oldRefreshToken))))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.success").value(true))
                .andExpect(jsonPath("$.data.accessToken").isNotEmpty())
                .andExpect(jsonPath("$.data.refreshToken").isNotEmpty())
                .andReturn();

        String newRefreshToken = jsonNode(refreshResult).path("data").path("refreshToken").asText();
        assertThat(newRefreshToken).isNotEqualTo(oldRefreshToken);
        Integer revokedCount = jdbcTemplate.queryForObject(
                "SELECT COUNT(*) FROM refresh_tokens WHERE revoked_at IS NOT NULL",
                Integer.class);
        assertThat(revokedCount).isEqualTo(1);
    }

    @Test
    void refreshWithRevokedRefreshTokenFails() throws Exception {
        register("alice", "password123");
        JsonNode login = login("alice", "password123");
        String accessToken = login.path("data").path("accessToken").asText();
        String refreshToken = login.path("data").path("refreshToken").asText();

        mockMvc.perform(post("/api/v1/auth/logout")
                        .header("Authorization", "Bearer " + accessToken)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(json(Map.of("refreshToken", refreshToken))))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.success").value(true));

        mockMvc.perform(post("/api/v1/auth/refresh")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(json(Map.of("refreshToken", refreshToken))))
                .andExpect(status().isUnauthorized())
                .andExpect(jsonPath("$.success").value(false))
                .andExpect(jsonPath("$.code").value("AUTH_TOKEN_REVOKED"));
    }

    @Test
    void logoutRevokesProvidedRefreshToken() throws Exception {
        register("alice", "password123");
        JsonNode login = login("alice", "password123");
        String accessToken = login.path("data").path("accessToken").asText();
        String refreshToken = login.path("data").path("refreshToken").asText();

        mockMvc.perform(post("/api/v1/auth/logout")
                        .header("Authorization", "Bearer " + accessToken)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(json(Map.of("refreshToken", refreshToken))))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.success").value(true));

        Integer revokedCount = jdbcTemplate.queryForObject(
                "SELECT COUNT(*) FROM refresh_tokens WHERE revoked_at IS NOT NULL",
                Integer.class);
        assertThat(revokedCount).isEqualTo(1);
    }

    @Test
    void logoutDoesNotRevokeAnotherUsersRefreshToken() throws Exception {
        register("alice", "password123");
        register("bob", "password123");
        String aliceAccessToken = login("alice", "password123").path("data").path("accessToken").asText();
        String bobRefreshToken = login("bob", "password123").path("data").path("refreshToken").asText();
        Long bobId = userId("bob");

        mockMvc.perform(post("/api/v1/auth/logout")
                        .header("Authorization", "Bearer " + aliceAccessToken)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(json(Map.of("refreshToken", bobRefreshToken))))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.success").value(true));

        Integer bobRevokedCount = jdbcTemplate.queryForObject(
                "SELECT COUNT(*) FROM refresh_tokens WHERE user_id = ? AND revoked_at IS NOT NULL",
                Integer.class,
                bobId);
        assertThat(bobRevokedCount).isZero();
    }

    private void register(String username, String password) throws Exception {
        mockMvc.perform(post("/api/v1/auth/register")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(json(Map.of("username", username, "password", password))))
                .andExpect(status().isOk());
    }

    private JsonNode login(String username, String password) throws Exception {
        MvcResult result = mockMvc.perform(post("/api/v1/auth/login")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(json(Map.of("username", username, "password", password))))
                .andExpect(status().isOk())
                .andReturn();
        return jsonNode(result);
    }

    private Long userId(String username) {
        return jdbcTemplate.queryForObject("SELECT id FROM users WHERE username = ?", Long.class, username);
    }

    private String json(Object value) throws Exception {
        return objectMapper.writeValueAsString(value);
    }

    private JsonNode jsonNode(MvcResult result) throws Exception {
        return objectMapper.readTree(result.getResponse().getContentAsString());
    }
}
