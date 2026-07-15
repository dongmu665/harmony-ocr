package com.harmonyocr.admin;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.time.LocalDateTime;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.web.client.TestRestTemplate;
import org.springframework.http.HttpEntity;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpMethod;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.context.ActiveProfiles;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * Admin Web Console 前后端 HTTP 联调测试。
 * 维护说明：本测试启动真实 Web 端口，通过 HTTP 调用 `/admin/console` 与后台 API；
 * 管理员身份只在测试库中 seed，不写入固定密码、Token、激活码明文、对象存储标识或 OCR 正文到日志。
 */
@ActiveProfiles("test")
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
class AdminConsoleHttpIntegrationTest {

    @Autowired
    private TestRestTemplate restTemplate;

    @Autowired
    private ObjectMapper objectMapper;

    @Autowired
    private JdbcTemplate jdbcTemplate;

    @BeforeEach
    void cleanDatabase() {
        jdbcTemplate.update("DELETE FROM admin_audit_logs");
        jdbcTemplate.update("DELETE FROM manual_membership_orders");
        jdbcTemplate.update("DELETE FROM membership_activation_codes");
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

    @Test
    void adminConsoleRunsAuthenticatedHttpFlowWithDesensitizedResponses() throws Exception {
        ResponseEntity<String> console = restTemplate.getForEntity("/admin/console", String.class);
        assertThat(console.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(console.getHeaders().getContentType()).isNotNull();
        assertThat(console.getHeaders().getContentType().toString()).contains("text/html", "UTF-8");
        assertThat(console.getBody())
                .contains("Harmony OCR Admin Console")
                .contains("/admin/assets/")
                .contains("/api/v1/auth/login")
                .contains("/api/v1/admin/me")
                .contains("/api/v1/admin/users")
                .contains("/api/v1/admin/activation-codes")
                .contains("/api/v1/users/me/password")
                .doesNotContain("POST /api/v1/admin/login")
                .doesNotContain("passwordHash")
                .doesNotContain("objectKey");

        assertAdminAssetIsPubliclyLoadable(console.getBody());

        String suffix = UUID.randomUUID().toString().replace("-", "").substring(0, 10);
        String adminUsername = "admin_http_" + suffix;
        String userUsername = "user_http_" + suffix;
        String adminPassword = "AdminHttp!" + suffix;
        String userPassword = "UserHttp!" + suffix;
        Long adminUserId = register(adminUsername, adminPassword);
        Long userId = register(userUsername, userPassword);
        seedAdmin(adminUserId);

        String adminToken = login(adminUsername, adminPassword).path("accessToken").asText();
        String userToken = login(userUsername, userPassword).path("accessToken").asText();

        ResponseEntity<String> forbidden = exchange(
                HttpMethod.GET,
                "/api/v1/admin/me",
                null,
                userToken);
        assertThat(forbidden.getStatusCode()).isEqualTo(HttpStatus.FORBIDDEN);
        assertThat(json(forbidden).path("code").asText()).isEqualTo("FORBIDDEN");

        JsonNode adminMe = data(exchange(HttpMethod.GET, "/api/v1/admin/me", null, adminToken));
        assertThat(adminMe.path("admin").asBoolean()).isTrue();

        JsonNode currentProfile = data(exchange(HttpMethod.GET, "/api/v1/users/me", null, adminToken));
        assertThat(currentProfile.path("username").asText()).isEqualTo(adminUsername);
        assertThat(currentProfile.has("passwordHash")).isFalse();

        JsonNode updatedProfile = data(exchange(
                HttpMethod.PATCH,
                "/api/v1/users/me",
                Map.of("nickname", "Admin Console HTTP"),
                adminToken));
        assertThat(updatedProfile.path("nickname").asText()).isEqualTo("Admin Console HTTP");
        assertThat(updatedProfile.has("accessToken")).isFalse();

        ResponseEntity<String> passwordChanged = exchange(
                HttpMethod.PATCH,
                "/api/v1/users/me/password",
                Map.of("currentPassword", adminPassword, "newPassword", "AdminHttpNew!" + suffix),
                adminToken);
        assertThat(passwordChanged.getStatusCode()).isEqualTo(HttpStatus.OK);

        data(exchange(
                HttpMethod.POST,
                "/api/v1/records",
                Map.of(
                        "title", "admin-http-contract-" + suffix,
                        "sourceType", "camera",
                        "rawText", "private admin HTTP verifier text that must stay out of admin responses",
                        "editedText", "private admin HTTP verifier text that must stay out of admin responses",
                        "language", "zh-CN",
                        "ocrEngine", "http-test"),
                userToken));

        Long feedbackId = data(exchange(
                HttpMethod.POST,
                "/api/v1/feedback",
                Map.of(
                        "feedbackType", "bug",
                        "content", "Admin console verifier feedback body remains private."),
                userToken)).path("id").asLong();

        JsonNode summary = data(exchange(HttpMethod.GET, "/api/v1/admin/usage/summary", null, adminToken));
        assertThat(summary.path("totalUsers").asLong()).isGreaterThanOrEqualTo(2);

        JsonNode users = data(exchange(
                HttpMethod.GET,
                "/api/v1/admin/users?keyword=" + userUsername + "&page=0&size=50",
                null,
                adminToken));
        assertThat(users.path("items").size()).isEqualTo(1);
        assertThat(users.path("items").get(0).path("id").asLong()).isEqualTo(userId);
        assertNoSensitiveFields(users.toString());

        JsonNode userDetail = data(exchange(HttpMethod.GET, "/api/v1/admin/users/" + userId, null, adminToken));
        assertThat(userDetail.path("username").asText()).isEqualTo(userUsername);
        assertNoSensitiveFields(userDetail.toString());

        JsonNode membership = data(exchange(
                HttpMethod.PATCH,
                "/api/v1/admin/users/" + userId + "/membership",
                Map.of("membershipLevel", "PRO", "ocrQuota", 30, "aiQuota", 5, "exportQuota", 3),
                adminToken));
        assertThat(membership.path("membershipLevel").asText()).isEqualTo("PRO");

        JsonNode manualOrder = data(exchange(
                HttpMethod.POST,
                "/api/v1/admin/users/" + userId + "/manual-orders",
                Map.of("membershipLevel", "TEAM", "ocrQuota", 40, "aiQuota", 6, "exportQuota", 4, "note", "HTTP verifier manual order"),
                adminToken));
        assertThat(manualOrder.path("paymentProvider").asText()).isEqualTo("MANUAL");
        assertNoSensitiveFields(manualOrder.toString());

        JsonNode createdCodes = data(exchange(
                HttpMethod.POST,
                "/api/v1/admin/activation-codes",
                Map.of(
                        "membershipLevel", "PRO",
                        "ocrQuota", 10,
                        "aiQuota", 2,
                        "exportQuota", 1,
                        "expiresAt", LocalDateTime.now().plusDays(7).withNano(0).toString(),
                        "count", 1,
                        "note", "HTTP verifier"),
                adminToken));
        JsonNode firstCode = createdCodes.path("codes").get(0);
        Long codeId = firstCode.path("id").asLong();
        assertThat(firstCode.path("code").asText()).isNotBlank();
        assertThat(firstCode.path("codeFingerprint").asText()).isNotBlank();

        JsonNode codeList = data(exchange(HttpMethod.GET, "/api/v1/admin/activation-codes", null, adminToken));
        assertThat(codeList.toString()).doesNotContain(firstCode.path("code").asText());
        assertThat(codeList.toString()).doesNotContain("codeHash");

        JsonNode revokedCode = data(exchange(HttpMethod.POST, "/api/v1/admin/activation-codes/" + codeId + "/revoke", null, adminToken));
        assertThat(revokedCode.path("status").asText()).isEqualTo("REVOKED");

        JsonNode records = data(exchange(
                HttpMethod.GET,
                "/api/v1/admin/records?userId=" + userId + "&sourceType=camera&keyword=contract&page=0&size=50",
                null,
                adminToken));
        assertThat(records.path("items").size()).isEqualTo(1);
        assertThat(records.toString())
                .doesNotContain("private admin HTTP verifier text")
                .doesNotContain("rawText")
                .doesNotContain("editedText")
                .doesNotContain("objectKey");

        JsonNode feedback = data(exchange(
                HttpMethod.GET,
                "/api/v1/admin/feedback?userId=" + userId + "&feedbackType=BUG&page=0&size=50",
                null,
                adminToken));
        assertThat(feedback.path("items").size()).isEqualTo(1);
        assertThat(feedback.toString())
                .doesNotContain("Admin console verifier feedback body")
                .doesNotContain("content")
                .doesNotContain("contact");

        JsonNode updatedFeedback = data(exchange(
                HttpMethod.PATCH,
                "/api/v1/admin/feedback/" + feedbackId + "/status",
                Map.of("status", "PROCESSING"),
                adminToken));
        assertThat(updatedFeedback.path("status").asText()).isEqualTo("PROCESSING");
        assertThat(updatedFeedback.toString()).doesNotContain("content");

        JsonNode audits = data(exchange(
                HttpMethod.GET,
                "/api/v1/admin/audit-logs?action=ADMIN_UPDATE_FEEDBACK_STATUS&targetType=FEEDBACK&targetId=" + feedbackId + "&page=0&size=50",
                null,
                adminToken));
        assertThat(audits.path("items").size()).isEqualTo(1);
        assertNoSensitiveFields(audits.toString());
    }

    private Long register(String username, String password) throws Exception {
        ResponseEntity<String> response = exchange(
                HttpMethod.POST,
                "/api/v1/auth/register",
                Map.of("username", username, "password", password, "nickname", username),
                "");
        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        return data(response).path("id").asLong();
    }

    private JsonNode login(String username, String password) throws Exception {
        ResponseEntity<String> response = exchange(
                HttpMethod.POST,
                "/api/v1/auth/login",
                Map.of("username", username, "password", password, "deviceId", "admin-console-http", "deviceName", "Admin Console HTTP Test"),
                "");
        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        return data(response);
    }

    private void seedAdmin(Long userId) {
        jdbcTemplate.update("""
                INSERT INTO admin_accounts (user_id, role, created_at)
                VALUES (?, 'ADMIN', CURRENT_TIMESTAMP)
                """, userId);
    }

    private void assertAdminAssetIsPubliclyLoadable(String html) {
        Matcher matcher = Pattern.compile("/admin/assets/[^\"']+").matcher(html);
        assertThat(matcher.find()).isTrue();
        ResponseEntity<String> asset = restTemplate.getForEntity(matcher.group(), String.class);
        assertThat(asset.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(asset.getBody()).isNotBlank();
    }

    private ResponseEntity<String> exchange(HttpMethod method, String path, Object body, String token) {
        HttpHeaders headers = new HttpHeaders();
        headers.setAccept(List.of(MediaType.APPLICATION_JSON));
        if (body != null) {
            headers.setContentType(MediaType.APPLICATION_JSON);
        }
        if (token != null && !token.isBlank()) {
            headers.setBearerAuth(token);
        }
        return restTemplate.exchange(path, method, new HttpEntity<>(body, headers), String.class);
    }

    private JsonNode data(ResponseEntity<String> response) throws Exception {
        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        return json(response).path("data");
    }

    private JsonNode json(ResponseEntity<String> response) throws Exception {
        return objectMapper.readTree(response.getBody());
    }

    private void assertNoSensitiveFields(String payload) {
        assertThat(payload)
                .doesNotContain("passwordHash")
                .doesNotContain("accessToken")
                .doesNotContain("refreshToken")
                .doesNotContain("apiKey")
                .doesNotContain("codeHash")
                .doesNotContain("objectKey");
    }
}
