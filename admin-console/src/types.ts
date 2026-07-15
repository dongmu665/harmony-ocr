import type { ReactNode } from "react";

export type ModuleKey =
  | "overview"
  | "users"
  | "quota"
  | "codes"
  | "records"
  | "feedback"
  | "audit"
  | "account";

export interface ResultEnvelope<T> {
  success?: boolean;
  code?: string;
  message?: string;
  data?: T;
}

export interface PageResult<T> {
  items?: T[];
  content?: T[];
  records?: T[];
  total?: number;
  totalElements?: number;
  page?: number;
  size?: number;
}

export interface AuthResponse {
  [key: string]: string | undefined;
}

export interface SessionUser {
  id?: number;
  username?: string;
  nickname?: string;
  status?: string;
  createdAt?: string;
  lastLoginAt?: string;
}

export interface AdminUser {
  id: number;
  username?: string;
  nickname?: string;
  status?: string;
  membershipLevel?: string;
  ocrQuota?: number;
  aiQuota?: number;
  exportQuota?: number;
  createdAt?: string;
  lastLoginAt?: string;
}

export interface UsageSummary {
  totalUsers?: number;
  activeUsers?: number;
  totalRecords?: number;
  totalFeedback?: number;
  openFeedback?: number;
  ocrUsed?: number;
  aiUsed?: number;
  exportUsed?: number;
  ocrUsage?: number;
  aiUsage?: number;
  exportUsage?: number;
}

export interface AuditLog {
  id: number;
  adminUserId?: number;
  action?: string;
  targetType?: string;
  targetId?: number | string;
  createdAt?: string;
}

export interface ActivationCode {
  id: number;
  code?: string;
  codeFingerprint?: string;
  membershipLevel?: string;
  ocrQuota?: number;
  aiQuota?: number;
  exportQuota?: number;
  status?: string;
  expiresAt?: string;
  redeemedByUserId?: number;
  redeemedAt?: string;
  note?: string;
}

export interface RecordRow {
  id: number;
  userId?: number;
  title?: string;
  sourceType?: string;
  textLength?: number;
  createdAt?: string;
}

export interface FeedbackRow {
  id: number;
  userId?: number;
  feedbackType?: string;
  status?: string;
  createdAt?: string;
}

export interface ToastMessage {
  id: number;
  type: "success" | "error" | "info";
  title: string;
  body?: string;
}

export interface ConfirmState {
  title: string;
  body: ReactNode;
  tone?: "danger" | "brand" | "warn";
  confirmText?: string;
  onConfirm: () => Promise<void> | void;
}
