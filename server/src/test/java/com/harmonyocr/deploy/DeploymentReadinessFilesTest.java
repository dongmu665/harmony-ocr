package com.harmonyocr.deploy;

import java.nio.file.Files;
import java.nio.file.Path;
import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * 生产部署就绪文件测试，属于 deploy 模块。
 * 维护说明：只检查公开模板和清单存在，不读取真实 .env，不要求 Docker 镜像或外部网络。
 * 备份方案由运营方在仓库外维护，公开源码只保留相应的回滚边界说明。
 */
class DeploymentReadinessFilesTest {

    private static final Path ROOT = Path.of("..").toAbsolutePath().normalize();

    @Test
    void productionDeploymentTemplatesAndReadinessChecklistExist() {
        assertThat(Files.exists(ROOT.resolve("deploy/docker-compose.prod.yml"))).isTrue();
        assertThat(Files.exists(ROOT.resolve("deploy/env.production.example"))).isTrue();
        assertThat(Files.exists(ROOT.resolve("deploy/nginx/harmony-ocr.conf.template"))).isTrue();
        assertThat(Files.exists(ROOT.resolve("deploy/rollback-plan.md"))).isTrue();
        assertThat(Files.exists(ROOT.resolve("deploy/release-checklist.md"))).isTrue();
    }

    @Test
    void productionDeploymentTemplatesExposeFailoverAndRollbackReadiness() throws Exception {
        String compose = Files.readString(ROOT.resolve("deploy/docker-compose.prod.yml"));
        String envExample = Files.readString(ROOT.resolve("deploy/env.production.example"));
        String rollbackPlan = Files.readString(ROOT.resolve("deploy/rollback-plan.md"));
        String checklist = Files.readString(ROOT.resolve("deploy/release-checklist.md"));

        assertThat(compose).contains("OCR_FAILOVER_ENABLED").contains("AI_FAILOVER_ENABLED");
        assertThat(envExample).contains("OCR_FAILOVER_ENABLED=false").contains("AI_FAILOVER_ENABLED=false");
        assertThat(rollbackPlan).contains("operator-controlled backup plan maintained outside this source repository");
        assertThat(checklist).contains("docker compose").contains("backup").contains("restore");
    }
}
