package com.harmonyocr.file.validation;

import com.harmonyocr.common.error.BusinessException;
import com.harmonyocr.common.error.ErrorCode;
import java.nio.ByteBuffer;
import java.nio.charset.CharacterCodingException;
import java.nio.charset.CodingErrorAction;
import java.nio.charset.StandardCharsets;
import java.util.Locale;

/**
 * 文件内容类型检测器，属于 file validation 模块。
 * 维护说明：客户端声明的 Content-Type 不可信，上传必须结合文件魔数或文本内容特征校验，防止脚本或二进制伪装为允许类型。
 */
public final class FileTypeDetector {

    private static final byte[] PNG_MAGIC = new byte[]{
            (byte) 0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A
    };

    private FileTypeDetector() {
    }

    /**
     * 校验声明类型与文件内容是否匹配。
     * 参数为已规范化 Content-Type 和完整文件内容；返回值为空。若内容为空、未知或声明与实际不匹配，则抛出 FILE_TYPE_NOT_ALLOWED。
     */
    public static void requireContentMatches(String contentType, byte[] content) {
        if (content == null || content.length == 0) {
            throw new BusinessException(ErrorCode.FILE_TYPE_NOT_ALLOWED);
        }
        String normalized = contentType == null ? "" : contentType.toLowerCase(Locale.ROOT);
        boolean matched = switch (normalized) {
            case "image/jpeg" -> isJpeg(content);
            case "image/png" -> startsWith(content, PNG_MAGIC);
            case "image/webp" -> isWebp(content);
            case "application/pdf" -> startsWith(content, "%PDF-".getBytes(StandardCharsets.US_ASCII));
            case "text/plain" -> isPlainText(content);
            default -> false;
        };
        if (!matched) {
            throw new BusinessException(ErrorCode.FILE_TYPE_NOT_ALLOWED);
        }
    }

    private static boolean isJpeg(byte[] content) {
        return content.length >= 3
                && (content[0] & 0xFF) == 0xFF
                && (content[1] & 0xFF) == 0xD8
                && (content[2] & 0xFF) == 0xFF;
    }

    private static boolean isWebp(byte[] content) {
        return content.length >= 12
                && content[0] == 'R'
                && content[1] == 'I'
                && content[2] == 'F'
                && content[3] == 'F'
                && content[8] == 'W'
                && content[9] == 'E'
                && content[10] == 'B'
                && content[11] == 'P';
    }

    private static boolean startsWith(byte[] content, byte[] prefix) {
        if (content.length < prefix.length) {
            return false;
        }
        for (int i = 0; i < prefix.length; i++) {
            if (content[i] != prefix[i]) {
                return false;
            }
        }
        return true;
    }

    private static boolean isPlainText(byte[] content) {
        int suspiciousControls = 0;
        for (byte value : content) {
            int unsigned = value & 0xFF;
            if (unsigned == 0) {
                return false;
            }
            if (unsigned < 0x20 && unsigned != '\n' && unsigned != '\r' && unsigned != '\t') {
                suspiciousControls++;
            }
        }
        if (suspiciousControls > Math.max(2, content.length / 20)) {
            return false;
        }
        try {
            StandardCharsets.UTF_8.newDecoder()
                    .onMalformedInput(CodingErrorAction.REPORT)
                    .onUnmappableCharacter(CodingErrorAction.REPORT)
                    .decode(ByteBuffer.wrap(content));
            return true;
        } catch (CharacterCodingException ex) {
            return false;
        }
    }
}
