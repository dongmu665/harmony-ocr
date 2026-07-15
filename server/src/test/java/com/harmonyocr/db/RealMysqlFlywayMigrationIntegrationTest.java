package com.harmonyocr.db;

import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.Statement;
import java.time.format.DateTimeFormatter;
import java.time.LocalDateTime;
import org.flywaydb.core.Flyway;
import org.flywaydb.core.api.MigrationInfo;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.condition.EnabledIfSystemProperty;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * 真实 MySQL Flyway 迁移验证，属于数据库发布验收测试。
 * 维护说明：该测试默认关闭，只在本地 V1.0 release readiness 中通过系统属性启用；
 * 测试会创建临时 schema 并在 finally 中删除，不连接生产库，不输出数据库密码。
 */
@EnabledIfSystemProperty(named = "harmonyocr.realMysql", matches = "true")
class RealMysqlFlywayMigrationIntegrationTest {

    @Test
    void migrationsApplySuccessfullyAgainstTemporaryLocalMysqlSchema() throws Exception {
        String schema = temporarySchemaName();
        String adminUrl = mysqlAdminUrl();
        String schemaUrl = mysqlSchemaUrl(schema);
        String username = envOrDefault("MYSQL_ROOT_USER", "root");
        String password = requiredEnv("MYSQL_ROOT_PASSWORD");

        try (Connection connection = DriverManager.getConnection(adminUrl, username, password);
             Statement statement = connection.createStatement()) {
            statement.execute("CREATE DATABASE `" + schema + "` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci");
        }

        try {
            Flyway flyway = Flyway.configure()
                    .dataSource(schemaUrl, username, password)
                    .locations("classpath:db/migration")
                    .load();
            flyway.migrate();

            MigrationInfo current = flyway.info().current();
            assertThat(current).isNotNull();
            assertThat(current.getVersion().getVersion()).isEqualTo("6");
        } finally {
            try (Connection connection = DriverManager.getConnection(adminUrl, username, password);
                 Statement statement = connection.createStatement()) {
                statement.execute("DROP DATABASE IF EXISTS `" + schema + "`");
            }
        }
    }

    /**
     * 生成本轮测试专用 schema 名称。
     * 返回值仅包含字母、数字和下划线，避免拼接 SQL 时引入注入风险。
     */
    private String temporarySchemaName() {
        String suffix = DateTimeFormatter.ofPattern("yyyyMMddHHmmss").format(LocalDateTime.now());
        return "harmony_ocr_verify_" + suffix;
    }

    private String mysqlAdminUrl() {
        return "jdbc:mysql://127.0.0.1:" + mysqlPort()
                + "/?useUnicode=true&characterEncoding=utf8&useSSL=false&serverTimezone=Asia/Shanghai&allowPublicKeyRetrieval=true";
    }

    private String mysqlSchemaUrl(String schema) {
        return "jdbc:mysql://127.0.0.1:" + mysqlPort() + "/" + schema
                + "?useUnicode=true&characterEncoding=utf8&useSSL=false&serverTimezone=Asia/Shanghai&allowPublicKeyRetrieval=true";
    }

    private String mysqlPort() {
        return envOrDefault("MYSQL_PORT", "3307");
    }

    private String requiredEnv(String name) {
        String value = System.getenv(name);
        assertThat(value)
                .as(name + " must be set for local real MySQL migration verification")
                .isNotBlank();
        return value;
    }

    private String envOrDefault(String name, String defaultValue) {
        String value = System.getenv(name);
        if (value == null || value.isBlank()) {
            return defaultValue;
        }
        return value;
    }
}
