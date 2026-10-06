export type CompanyStatus = 'PENDING_VERIFICATION' | 'TRIAL' | 'ACTIVE' | 'SUSPENDED' | 'DEACTIVATED';
export const COMPANY_STATUSES: CompanyStatus[] = ['PENDING_VERIFICATION', 'TRIAL', 'ACTIVE', 'SUSPENDED', 'DEACTIVATED'];

// A plan code is a Super-Admin-managed catalog entry (see SubscriptionPlanDefinition below), not a fixed set; kept as a type alias so existing import sites keep compiling.
export type SubscriptionPlan = string;

export type BillingCycle = 'MONTHLY' | 'YEARLY';

// Mirrors backend SubscriptionPlanDefinition (GET/POST/PATCH /api/subscription-plans)
export interface SubscriptionPlanDefinition {
  id: number;
  code: string;
  name: string;
  description?: string;
  billingCycle: BillingCycle;
  price: number;
  active: boolean;
  createdAt: string;
  updatedAt?: string;
}

export interface SubscriptionPlanRequest {
  code: string;
  name: string;
  description?: string;
  billingCycle: BillingCycle;
  price: number;
}

export type PlatformRole =
  | 'SUPER_ADMIN' | 'SYSTEM_ADMIN' | 'SUPPORT_AGENT' | 'SUPPORT_MANAGER'
  | 'MARKETING_MANAGER' | 'PLATFORM_ACCOUNTANT' | 'SALES_MANAGER'
  | 'COMPANY_OWNER' | 'CLIENT' | 'EMPLOYEE';
export const PLATFORM_ROLES: PlatformRole[] = [
  'SUPER_ADMIN', 'SYSTEM_ADMIN', 'SUPPORT_AGENT', 'SUPPORT_MANAGER',
  'MARKETING_MANAGER', 'PLATFORM_ACCOUNTANT', 'SALES_MANAGER',
];

export interface Company {
  id: number;
  companyName: string;
  subdomain: string;
  companyEmail?: string;
  companyPhone?: string;
  website?: string;
  logo?: string;
  primaryColor?: string;
  secondaryColor?: string;
  tagline?: string;
  status: CompanyStatus;
  subscriptionPlan: SubscriptionPlan;
  subscriptionStart?: string;
  subscriptionEnd?: string;
  trialExpired: boolean;
  ownerId?: number;
  ownerName?: string;
  ownerEmail?: string;
  createdAt: string;
  location?: string;
  portalAbout?: string;
  locationDetail?: import('../../../shared/models/location.model').LocationResponse;
}

export interface RegisterCompanyRequest {
  companyName: string;
  subdomain: string;
  ownerFirstName: string;
  ownerLastName: string;
  ownerEmail: string;
  ownerPassword: string;
  companyPhone?: string;
}

export interface PlatformUser {
  id: number;
  firstName: string;
  lastName: string;
  email: string;
  phone?: string;
  image?: string;
  role: PlatformRole;
  active: boolean;
  emailVerified: boolean;
  languagePreference?: string;
  createdAt: string;
}

export interface PlatformUserRequest {
  firstName: string;
  lastName: string;
  email: string;
  password: string;
  role: PlatformRole;
  phone?: string;
}

export interface CustomRole {
  id: number;
  name: string;
  description?: string;
  active: boolean;
  systemRole: boolean;
}

export interface CustomRoleRequest {
  name: string;
  description?: string;
}

// Subscription history (plan-change audit trail, feeds platform revenue stats)
export interface SubscriptionHistory {
  id: number;
  companyId?: number;
  companyName?: string;
  fromPlan: SubscriptionPlan;
  toPlan: SubscriptionPlan;
  subscriptionStart?: string;
  subscriptionEnd?: string;
  amountPaid?: number;
  transactionRef?: string;
  notes?: string;
  changedAt: string;
  changedById?: number;
  changedByName?: string;
}

export interface FeatureFlag {
  id: number;
  flagKey: string;
  enabled: boolean;
  description?: string;
  updatedAt?: string;
}

// "Platform Employee" is the same concept as PlatformUser, not a separate payroll entity; platform-staff payroll would be its own feature.
