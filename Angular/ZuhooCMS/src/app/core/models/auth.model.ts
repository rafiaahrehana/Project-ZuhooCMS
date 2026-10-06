// Mirrors backend DTOs in com.businessos.auth.* and com.businessos.platform.company.

export interface LoginRequest {
  email: string;
  password: string;
}

export interface RegisterRequest {
  firstName: string;
  lastName: string;
  email: string;
  password: string;
  companyName: string;
  subdomain: string;
  companyPhone?: string;
}

// POST /api/auth/login response shape
export interface LoginResponse {
  userId: number;
  firstName: string;
  email: string;
  role: string;
  companyId: number | null;
  accessToken: string;
  refreshToken: string;
}

// POST /api/auth/refresh response shape (tokens only - no user info)
export interface JwtResponse {
  accessToken: string;
  refreshToken: string;
}

export interface VerifyEmailRequest {
  email: string;
  code: string;
}

export interface ResendVerificationRequest {
  email: string;
}

export interface ForgotPasswordRequest {
  email: string;
}

// Pre-check only: does not consume the code - resetPassword() re-validates it for real.
export interface VerifyResetCodeRequest {
  email: string;
  code: string;
}

// Mutually exclusive: email + code (forgot-password flow) or token (client-portal invite link); reset-password.ts sends only whichever query param is present.
export interface ResetPasswordRequest {
  email?: string;
  code?: string;
  token?: string;
  newPassword: string;
  confirmPassword: string;
}

// Mirrors backend ChangePasswordRequest (POST /api/auth/change-password).
export interface ChangePasswordRequest {
  currentPassword: string;
  newPassword: string;
  confirmPassword: string;
}

export interface User {
  id: number;
  username: string;
  email: string;
  fullName: string;
  roles: string[];
  companyId?: number | null;
  profileImageUrl?: string;
}

export interface TokenPayload {
  sub: string;
  role: string;
  companyId?: number;
  actionType?: string;
  exp: number;
  iat: number;
}

// POST /api/platform-admin/companies/{id}/impersonate response shape
export interface ImpersonationResponse {
  accessToken: string;
  companyId: number;
  companyName: string;
  impersonationSessionId: string;
  expiresInSeconds: number;
}

// Local (frontend-only) bookkeeping for the "Viewing as {company}" banner
export interface ImpersonationSession {
  companyId: number;
  companyName: string;
  impersonationSessionId: string;
  expiresAt: number; // epoch ms
}
