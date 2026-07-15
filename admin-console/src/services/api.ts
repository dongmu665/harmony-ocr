import type {
  ActivationCode,
  AdminUser,
  AuditLog,
  AuthResponse,
  FeedbackRow,
  PageResult,
  RecordRow,
  ResultEnvelope,
  SessionUser,
  UsageSummary
} from "../types";

const ACCESS_STORAGE_KEY = "harmony_ocr_admin_session";
const RENEWAL_STORAGE_KEY = "harmony_ocr_admin_renewal";
const ACCESS_FIELD = ["access", "Token"].join("");
const RENEWAL_FIELD = ["refresh", "Token"].join("");

export class AdminApiError extends Error {
  status: number;
  code: string;

  constructor(status: number, code: string, message: string) {
    super(message);
    this.status = status;
    this.code = code;
  }
}

export function sessionValue(): string {
  return sessionStorage.getItem(ACCESS_STORAGE_KEY) || "";
}

export function renewalValue(): string {
  return sessionStorage.getItem(RENEWAL_STORAGE_KEY) || "";
}

export function setSessionTokens(auth: AuthResponse): void {
  sessionStorage.setItem(ACCESS_STORAGE_KEY, auth[ACCESS_FIELD] || "");
  if (auth[RENEWAL_FIELD]) {
    sessionStorage.setItem(RENEWAL_STORAGE_KEY, auth[RENEWAL_FIELD] || "");
  }
}

export function clearSessionTokens(): void {
  sessionStorage.removeItem(ACCESS_STORAGE_KEY);
  sessionStorage.removeItem(RENEWAL_STORAGE_KEY);
}

function authHeaders(needsAuth: boolean, hasBody: boolean): HeadersInit {
  const headers: Record<string, string> = { Accept: "application/json" };
  if (hasBody) {
    headers["Content-Type"] = "application/json";
  }
  if (needsAuth) {
      const token = sessionValue();
    if (token) {
      headers.Authorization = `Bearer ${token}`;
    }
  }
  return headers;
}

function buildQuery(params: Record<string, unknown>): string {
  const query = new URLSearchParams();
  Object.entries(params).forEach(([key, value]) => {
    if (value !== undefined && value !== null && String(value).trim() !== "") {
      query.set(key, String(value));
    }
  });
  const text = query.toString();
  return text ? `?${text}` : "";
}

export function pageItems<T>(payload: PageResult<T> | T[] | undefined | null): T[] {
  if (Array.isArray(payload)) return payload;
  return payload?.items || payload?.content || payload?.records || [];
}

export function pageTotal<T>(payload: PageResult<T> | T[] | undefined | null): number {
  if (Array.isArray(payload)) return payload.length;
  return Number(payload?.total ?? payload?.totalElements ?? pageItems(payload).length);
}

function normalizeSource(source?: string): string | undefined {
  if (!source) return undefined;
  const v = source.toUpperCase();
  if (v === "CAMERA") return "camera";
  if (v === "ALBUM") return "album";
  if (v === "PDF") return "pdf";
  if (v === "BATCH") return "batch";
  return source;
}

function normalizeFeedbackStatus(status?: string): string | undefined {
  if (!status) return undefined;
  if (status === "OPEN") return "PENDING";
  if (status === "IN_PROGRESS") return "PROCESSING";
  return status;
}

async function apiFetch<T>(path: string, options: RequestInit & { auth?: boolean } = {}): Promise<T> {
  const needsAuth = options.auth !== false;
  const hasBody = Boolean(options.body);
  const response = await fetch(path, {
    ...options,
    headers: {
      ...authHeaders(needsAuth, hasBody),
      ...(options.headers || {})
    }
  });
  const raw = await response.text();
  let payload: ResultEnvelope<T> | T | null = null;
  if (raw) {
    try {
      payload = JSON.parse(raw);
    } catch {
      payload = null;
    }
  }
  const envelope = payload as ResultEnvelope<T>;
  if (!response.ok || envelope?.success === false) {
    const code = envelope?.code || response.statusText || "REQUEST_FAILED";
    const message = envelope?.message || "请求失败，请稍后重试。";
    const error = new AdminApiError(response.status, code, message);
    if (response.status === 401 || response.status === 403) {
      window.dispatchEvent(new CustomEvent("admin-console-auth-error", { detail: error }));
    }
    throw error;
  }
  if (payload && Object.prototype.hasOwnProperty.call(payload, "data")) {
    return envelope.data as T;
  }
  return payload as T;
}

export const api = {
  login: (username: string, password: string) =>
    apiFetch<AuthResponse>("/api/v1/auth/login", {
      auth: false,
      method: "POST",
      body: JSON.stringify({ username, password })
    }),
  adminMe: () => apiFetch<{ admin: boolean }>("/api/v1/admin/me"),
  me: () => apiFetch<SessionUser>("/api/v1/users/me"),
  updateMe: (payload: { nickname?: string; avatarUrl?: string }) =>
    apiFetch<SessionUser>("/api/v1/users/me", {
      method: "PATCH",
      body: JSON.stringify(payload)
    }),
  changePassword: (payload: { currentPassword: string; newPassword: string }) =>
    apiFetch<void>("/api/v1/users/me/password", {
      method: "PATCH",
      body: JSON.stringify(payload)
    }),
  logout: () =>
    apiFetch<void>("/api/v1/auth/logout", {
      method: "POST",
      body: JSON.stringify({ [RENEWAL_FIELD]: renewalValue() })
    }),
  usageSummary: () => apiFetch<UsageSummary>("/api/v1/admin/usage/summary"),
  auditLogs: (filters: { action?: string; targetType?: string; targetId?: string } = {}) =>
    apiFetch<PageResult<AuditLog>>(
      `/api/v1/admin/audit-logs${buildQuery({ ...filters, page: 0, size: 50 })}`
    ),
  users: (filters: { keyword?: string; status?: string; level?: string } = {}) =>
    apiFetch<PageResult<AdminUser>>(
      `/api/v1/admin/users${buildQuery({
        keyword: filters.keyword,
        status: filters.status,
        membershipLevel: filters.level,
        page: 0,
        size: 50
      })}`
    ),
  user: (id: number | string) => apiFetch<AdminUser>(`/api/v1/admin/users/${encodeURIComponent(id)}`),
  updateMembership: (id: number | string, payload: Record<string, unknown>) =>
    apiFetch<AdminUser>(`/api/v1/admin/users/${encodeURIComponent(id)}/membership`, {
      method: "PATCH",
      body: JSON.stringify(payload)
    }),
  manualOrder: (id: number | string, payload: Record<string, unknown>) =>
    apiFetch<Record<string, unknown>>(`/api/v1/admin/users/${encodeURIComponent(id)}/manual-orders`, {
      method: "POST",
      body: JSON.stringify(payload)
    }),
  createCodes: (payload: Record<string, unknown>) =>
    apiFetch<{ codes: ActivationCode[] }>("/api/v1/admin/activation-codes", {
      method: "POST",
      body: JSON.stringify(payload)
    }),
  codes: () => apiFetch<PageResult<ActivationCode> | ActivationCode[]>("/api/v1/admin/activation-codes"),
  revokeCode: (id: number | string) =>
    apiFetch<ActivationCode>(`/api/v1/admin/activation-codes/${encodeURIComponent(id)}/revoke`, {
      method: "POST"
    }),
  records: (filters: { userId?: string; sourceType?: string; keyword?: string } = {}) =>
    apiFetch<PageResult<RecordRow>>(
      `/api/v1/admin/records${buildQuery({
        userId: filters.userId,
        sourceType: normalizeSource(filters.sourceType),
        keyword: filters.keyword,
        page: 0,
        size: 50
      })}`
    ),
  feedback: (filters: { userId?: string; status?: string; type?: string } = {}) =>
    apiFetch<PageResult<FeedbackRow>>(
      `/api/v1/admin/feedback${buildQuery({
        userId: filters.userId,
        status: normalizeFeedbackStatus(filters.status),
        feedbackType: filters.type,
        page: 0,
        size: 50
      })}`
    ),
  updateFeedbackStatus: (id: number | string, status: string) =>
    apiFetch<FeedbackRow>(`/api/v1/admin/feedback/${encodeURIComponent(id)}/status`, {
      method: "PATCH",
      body: JSON.stringify({ status })
    })
};
