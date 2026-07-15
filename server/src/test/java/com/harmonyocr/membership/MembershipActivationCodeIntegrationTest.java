package com.harmonyocr.membership;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.Callable;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.TimeUnit;
import org.junit.jupiter.api.AfterEach;
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
import static org.hamcrest.Matchers.hasKey;
import static org.hamcrest.Matchers.hasSize;
import static org.hamcrest.Matchers.not;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * 会员激活码集成测试，属于 membership/admin 模块。
 * 维护说明：测试只临时持有随机明文激活码用于兑换请求，不打印、不落库、不写入文档输出。
 */
@ActiveProfiles("test")
@AutoConfigureMockMvc
@SpringBootTest
class MembershipActivationCodeIntegrationTest {

    @Autowired
    private MockMvc mockMvc;

    @Autowired
    private ObjectMapper objectMapper;

    @Autowired
    private JdbcTemplate jdbcTemplate;

    @BeforeEach
    void cleanDatabase() {
        jdbcTemplate.update("DELETE FROM membership_activation_codes");
        jdbcTemplate.update("DELETE FROM admin_audit_logs");
        jdbcTemplate.update("DELETE FROM manual_membership_orders");
        jdbcTemplate.update("DELETE FROM usage_counters");
        jdbcTemplate.update("DELETE FROM user_memberships");
        jdbcTemplate.update("DELETE FROM admin_accounts");
        jdbcTemplate.update("DELETE FROM ai_runtime_consents");
        jdbcTemplate.update("DELETE FROM ai_provider_configs");
        jdbcTemplate.update("DELETE FROM object_storage_cleanup_tasks");
        jdbcTemplate.update("DELETE FROM file_objects");
        jdbcTemplate.update("DELETE FROM recognition_record_tags");
        jdbcTemplate.update("DELETE FROM recognition_tags");
        jdbcTemplate.update("DELETE FROM recognition_blocks");
        jdbcTemplate.update("DELETE FROM recognition_records");
        jdbcTemplate.update("DELETE FROM feedback");
        jdbcTemplate.update("DELETE FROM refresh_tokens");
        jdbcTemplate.update("DELETE FROM user_devices");
        jdbcTemplate.update("DELETE FROM export_jobs");
        jdbcTemplate.update("DELETE FROM batch_ocr_items");
        jdbcTemplate.update("DELETE FROM batch_ocr_jobs");
        jdbcTemplate.update("DELETE FROM users");
    }

    @AfterEach
    void cleanAfterTest() {
        jdbcTemplate.update("DELETE FROM membership_activation_codes");
    }

    @Test
    void ordinaryUserCannotAccessAdminActivationCodeApis() throws Exception {
        String adminPassword = testPassword();
        String alicePassword = testPassword();
        register("admin", adminPassword);
        register("alice", alicePassword);
        seedAdmin(userId("admin"));
        String aliceToken = bearer(accessToken("alice", alicePassword));

        mockMvc.perform(post("/api/v1/admin/activation-codes")
                        .header(HttpHeaders.AUTHORIZATION, aliceToken)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(json(createRequest("PRO", 1))))
                .andExpect(status().isForbidden())
                .andExpect(jsonPath("$.code").value("FORBIDDEN"));

        mockMvc.perform(get("/api/v1/admin/activation-codes")
                        .header(HttpHeaders.AUTHORIZATION, aliceToken))
                .andExpect(status().isForbidden())
                .andExpect(jsonPath("$.code").value("FORBIDDEN"));

        mockMvc.perform(post("/api/v1/admin/activation-codes/{id}/revoke", 1L)
                        .header(HttpHeaders.AUTHORIZATION, aliceToken))
                .andExpect(status().isForbidden())
                .andExpect(jsonPath("$.code").value("FORBIDDEN"));
    }

    @Test
    void adminCanGenerateProActivationCodeAndListDoesNotReturnPlainCode() throws Exception {
        String adminPassword = testPassword();
        register("admin", adminPassword);
        Long adminUserId = userId("admin");
        seedAdmin(adminUserId);
        String adminToken = bearer(accessToken("admin", adminPassword));

        MvcResult created = mockMvc.perform(post("/api/v1/admin/activation-codes")
                        .header(HttpHeaders.AUTHORIZATION, adminToken)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(json(createRequest("PRO", 1))))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.codes", hasSize(1)))
                .andExpect(jsonPath("$.data.codes[0].membershipLevel").value("PRO"))
                .andExpect(jsonPath("$.data.codes[0].ocrQuota").value(300))
                .andExpect(jsonPath("$.data.codes[0].code").isString())
                .andExpect(jsonPath("$.data.codes[0]", not(hasKey("codeHash"))))
                .andReturn();
        JsonNode codeNode = jsonNode(created).path("data").path("codes").get(0);
        String plainCode = codeNode.path("code").asText();
        Long codeId = codeNode.path("id").asLong();

        String storedHash = jdbcTemplate.queryForObject(
                "SELECT code_hash FROM membership_activation_codes WHERE id = ?",
                String.class,
                codeId);
        assertThat(plainCode).startsWith("PRO-");
        assertThat(storedHash).isNotBlank().isNotEqualTo(plainCode);

        mockMvc.perform(get("/api/v1/admin/activation-codes")
                        .header(HttpHeaders.AUTHORIZATION, adminToken))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data", hasSize(1)))
                .andExpect(jsonPath("$.data[0].id").value(codeId))
                .andExpect(jsonPath("$.data[0].codeFingerprint").isString())
                .andExpect(jsonPath("$.data[0].membershipLevel").value("PRO"))
                .andExpect(jsonPath("$.data[0].status").value("UNUSED"))
                .andExpect(jsonPath("$.data[0]", not(hasKey("code"))))
                .andExpect(jsonPath("$.data[0]", not(hasKey("codeHash"))));

        Integer audits = jdbcTemplate.queryForObject(
                "SELECT COUNT(*) FROM admin_audit_logs WHERE admin_user_id = ? AND action = 'ADMIN_CREATE_ACTIVATION_CODE'",
                Integer.class,
                adminUserId);
        assertThat(audits).isEqualTo(1);
    }

    @Test
    void userRedeemsProActivationCodeAndMembershipMeReflectsQuota() throws Exception {
        String adminPassword = testPassword();
        String alicePassword = testPassword();
        register("admin", adminPassword);
        register("alice", alicePassword);
        seedAdmin(userId("admin"));
        String adminToken = bearer(accessToken("admin", adminPassword));
        String aliceToken = bearer(accessToken("alice", alicePassword));
        String code = createActivationCode(adminToken, "PRO");

        mockMvc.perform(post("/api/v1/membership/activation-codes/redeem")
                        .header(HttpHeaders.AUTHORIZATION, aliceToken)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(json(Map.of("code", code))))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.membershipLevel").value("PRO"))
                .andExpect(jsonPath("$.data.ocrQuota").value(300))
                .andExpect(jsonPath("$.data.aiQuota").value(80))
                .andExpect(jsonPath("$.data.exportQuota").value(25));

        mockMvc.perform(get("/api/v1/membership/me")
                        .header(HttpHeaders.AUTHORIZATION, aliceToken))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.membershipLevel").value("PRO"))
                .andExpect(jsonPath("$.data.ocrQuota").value(300))
                .andExpect(jsonPath("$.data.aiQuota").value(80))
                .andExpect(jsonPath("$.data.exportQuota").value(25));

        Long redeemedBy = jdbcTemplate.queryForObject(
                "SELECT redeemed_by_user_id FROM membership_activation_codes",
                Long.class);
        String status = jdbcTemplate.queryForObject(
                "SELECT status FROM membership_activation_codes",
                String.class);
        assertThat(redeemedBy).isEqualTo(userId("alice"));
        assertThat(status).isEqualTo("REDEEMED");
    }

    @Test
    void sameActivationCodeCanOnlyBeRedeemedOnce() throws Exception {
        String adminPassword = testPassword();
        String alicePassword = testPassword();
        String bobPassword = testPassword();
        register("admin", adminPassword);
        register("alice", alicePassword);
        register("bob", bobPassword);
        seedAdmin(userId("admin"));
        String adminToken = bearer(accessToken("admin", adminPassword));
        String aliceToken = bearer(accessToken("alice", alicePassword));
        String bobToken = bearer(accessToken("bob", bobPassword));
        String code = createActivationCode(adminToken, "PRO");

        redeem(aliceToken, code).andExpect(status().isOk());
        redeem(bobToken, code)
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.code").value("VALIDATION_ERROR"))
                .andExpect(jsonPath("$.message").value("激活码无效、已使用或已过期"));

        Integer redeemed = jdbcTemplate.queryForObject(
                "SELECT COUNT(*) FROM membership_activation_codes WHERE status = 'REDEEMED'",
                Integer.class);
        Integer proUsers = jdbcTemplate.queryForObject(
                "SELECT COUNT(*) FROM user_memberships WHERE membership_level = 'PRO'",
                Integer.class);
        assertThat(redeemed).isEqualTo(1);
        assertThat(proUsers).isEqualTo(1);
    }

    @Test
    void expiredAndRevokedActivationCodesCannotBeRedeemed() throws Exception {
        String adminPassword = testPassword();
        String alicePassword = testPassword();
        register("admin", adminPassword);
        register("alice", alicePassword);
        seedAdmin(userId("admin"));
        String adminToken = bearer(accessToken("admin", adminPassword));
        String aliceToken = bearer(accessToken("alice", alicePassword));
        String expiredCode = createActivationCode(adminToken, "PRO", pastExpiresAt());
        MvcResult revoked = createActivationCodeResult(adminToken, "TEAM", futureExpiresAt());
        JsonNode revokedCodeNode = jsonNode(revoked).path("data").path("codes").get(0);
        String revokedCode = revokedCodeNode.path("code").asText();
        Long revokedCodeId = revokedCodeNode.path("id").asLong();

        mockMvc.perform(post("/api/v1/admin/activation-codes/{id}/revoke", revokedCodeId)
                        .header(HttpHeaders.AUTHORIZATION, adminToken))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.status").value("REVOKED"));

        redeem(aliceToken, expiredCode)
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value("激活码无效、已使用或已过期"));
        redeem(aliceToken, revokedCode)
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value("激活码无效、已使用或已过期"));

        String expiredStatus = jdbcTemplate.queryForObject(
                "SELECT status FROM membership_activation_codes WHERE membership_level = 'PRO'",
                String.class);
        assertThat(expiredStatus).isEqualTo("EXPIRED");
    }

    @Test
    void redeemedActivationCodeCannotBeRevoked() throws Exception {
        String adminPassword = testPassword();
        String alicePassword = testPassword();
        register("admin", adminPassword);
        register("alice", alicePassword);
        seedAdmin(userId("admin"));
        String adminToken = bearer(accessToken("admin", adminPassword));
        String aliceToken = bearer(accessToken("alice", alicePassword));
        MvcResult created = createActivationCodeResult(adminToken, "PRO", futureExpiresAt());
        JsonNode codeNode = jsonNode(created).path("data").path("codes").get(0);
        String code = codeNode.path("code").asText();
        Long codeId = codeNode.path("id").asLong();
        redeem(aliceToken, code).andExpect(status().isOk());

        mockMvc.perform(post("/api/v1/admin/activation-codes/{id}/revoke", codeId)
                        .header(HttpHeaders.AUTHORIZATION, adminToken))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.code").value("VALIDATION_ERROR"));
    }

    @Test
    void concurrentRedeemDoesNotAllowOneCodeToUpgradeMultipleUsers() throws Exception {
        String adminPassword = testPassword();
        String alicePassword = testPassword();
        String bobPassword = testPassword();
        register("admin", adminPassword);
        register("alice", alicePassword);
        register("bob", bobPassword);
        seedAdmin(userId("admin"));
        String adminToken = bearer(accessToken("admin", adminPassword));
        String aliceToken = bearer(accessToken("alice", alicePassword));
        String bobToken = bearer(accessToken("bob", bobPassword));
        String code = createActivationCode(adminToken, "PRO");

        ExecutorService executor = Executors.newFixedThreadPool(2);
        CountDownLatch start = new CountDownLatch(1);
        try {
            List<Callable<Integer>> calls = new ArrayList<>();
            calls.add(() -> redeemStatusAfterStart(start, aliceToken, code));
            calls.add(() -> redeemStatusAfterStart(start, bobToken, code));
            List<Future<Integer>> futures = calls.stream().map(executor::submit).toList();
            start.countDown();

            List<Integer> statuses = new ArrayList<>();
            for (Future<Integer> future : futures) {
                statuses.add(future.get(10, TimeUnit.SECONDS));
            }

            assertThat(statuses).containsExactlyInAnyOrder(200, 400);
            Integer redeemed = jdbcTemplate.queryForObject(
                    "SELECT COUNT(*) FROM membership_activation_codes WHERE status = 'REDEEMED'",
                    Integer.class);
            Integer proUsers = jdbcTemplate.queryForObject(
                    "SELECT COUNT(*) FROM user_memberships WHERE membership_level = 'PRO'",
                    Integer.class);
            assertThat(redeemed).isEqualTo(1);
            assertThat(proUsers).isEqualTo(1);
        } finally {
            executor.shutdownNow();
        }
    }

    private int redeemStatusAfterStart(CountDownLatch start, String token, String code) throws Exception {
        start.await(5, TimeUnit.SECONDS);
        return mockMvc.perform(post("/api/v1/membership/activation-codes/redeem")
                        .header(HttpHeaders.AUTHORIZATION, token)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(json(Map.of("code", code))))
                .andReturn()
                .getResponse()
                .getStatus();
    }

    private org.springframework.test.web.servlet.ResultActions redeem(String token, String code) throws Exception {
        return mockMvc.perform(post("/api/v1/membership/activation-codes/redeem")
                .header(HttpHeaders.AUTHORIZATION, token)
                .contentType(MediaType.APPLICATION_JSON)
                .content(json(Map.of("code", code))));
    }

    private String createActivationCode(String adminToken, String membershipLevel) throws Exception {
        MvcResult result = createActivationCodeResult(adminToken, membershipLevel, futureExpiresAt());
        return jsonNode(result).path("data").path("codes").get(0).path("code").asText();
    }

    private String createActivationCode(String adminToken, String membershipLevel, String expiresAt) throws Exception {
        MvcResult result = createActivationCodeResult(adminToken, membershipLevel, expiresAt);
        return jsonNode(result).path("data").path("codes").get(0).path("code").asText();
    }

    private MvcResult createActivationCodeResult(String adminToken, String membershipLevel, String expiresAt) throws Exception {
        return mockMvc.perform(post("/api/v1/admin/activation-codes")
                        .header(HttpHeaders.AUTHORIZATION, adminToken)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(json(createRequest(membershipLevel, 1, expiresAt))))
                .andExpect(status().isOk())
                .andReturn();
    }

    private Map<String, Object> createRequest(String membershipLevel, int count) {
        return createRequest(membershipLevel, count, futureExpiresAt());
    }

    private Map<String, Object> createRequest(String membershipLevel, int count, String expiresAt) {
        return Map.of(
                "membershipLevel", membershipLevel,
                "ocrQuota", 300,
                "aiQuota", 80,
                "exportQuota", 25,
                "expiresAt", expiresAt,
                "count", count,
                "note", "course activation");
    }

    private String futureExpiresAt() {
        return "2099-12-31T23:59:59";
    }

    private String pastExpiresAt() {
        return "2000-01-01T00:00:00";
    }

    private void seedAdmin(Long userId) {
        jdbcTemplate.update("""
                INSERT INTO admin_accounts (user_id, role, created_at)
                VALUES (?, 'SUPER_ADMIN', CURRENT_TIMESTAMP)
                """, userId);
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
