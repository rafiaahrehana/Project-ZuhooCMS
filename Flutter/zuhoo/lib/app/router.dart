import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/auth/auth_controller.dart';
import '../core/auth/permission_controller.dart';
import '../features/alerts/alerts_screen.dart';
import '../features/approvals/approvals_screen.dart';
import '../features/attendance/attendance_screen.dart';
import '../features/attendance/shift_roster_screen.dart';
import '../features/ai/ai_screen.dart';
import '../features/alerts/notification_preferences_screen.dart';
import '../features/attendance/team_attendance_screen.dart';
import '../features/auth/forgot_password_screen.dart';
import '../features/auth/login_screen.dart';
import '../features/auth/register_screen.dart';
import '../features/auth/verify_email_screen.dart';
import '../features/home/home_screen.dart';
import '../features/hrpolicy/hrpolicy_screen.dart';
import '../features/leave/leave_screen.dart';
import '../features/payslips/payslips_screen.dart';
import '../features/requests/requests_screen.dart';
import '../features/crm/contacts_screen.dart';
import '../features/support/support_queue_screen.dart';
import '../features/kb/kb_authoring_screen.dart';
import '../features/requests/reviews_screen.dart';
import '../features/ai/ai_drafts_screen.dart';
import '../features/ai/ai_settings_screen.dart';
import '../features/dashboard/dashboard_screen.dart';
import '../features/dashboard/platform_dashboard_screen.dart';
import '../features/crm/crm_reports_screen.dart';
import '../features/crm/crm_screen.dart';
import '../features/directory/directory_screen.dart';
import '../features/finance/finance_screen.dart';
import '../features/itam/itam_screen.dart';
import '../features/accounting/accounting_screen.dart';
import '../features/accounting/reconciliation_screen.dart';
import '../features/company/company_screen.dart';
import '../features/company/subscription_plan_screen.dart';
import '../features/leave/entitlements_screen.dart';
import '../features/admin/accounts_screen.dart';
import '../features/admin/admin_screen.dart';
import '../features/assets_periods/assets_periods_screen.dart';
import '../features/biometric/biometric_screen.dart';
import '../features/budgets/budget_screen.dart';
import '../features/catalogue/catalogue_screen.dart';
import '../features/payables/payables_screen.dart';
import '../features/payroll/payroll_screen.dart';
import '../features/payroll/salary_sheet_screen.dart';
import '../features/receivables/receivables_screen.dart';
import '../features/reports/report_screen.dart';
import '../features/salary/salary_screen.dart';
import '../features/support_admin/support_admin_screen.dart';
import '../features/workflow/workflow_screen.dart';
import '../features/kb/kb_screen.dart';
import '../features/performance/performance_screen.dart';
import '../features/search/search_screen.dart';
import '../features/recruitment/career_page_screen.dart';
import '../features/recruitment/recruitment_kpi_screen.dart';
import '../features/recruitment/recruitment_screen.dart';
import '../features/platform/locations_screen.dart';
import '../features/platform/platform_screen.dart';
import '../features/platform/plans_screen.dart';
import '../features/support/support_screen.dart';
import '../features/profile/appearance_screen.dart';
import '../features/profile/change_email_screen.dart';
import '../features/profile/change_password_screen.dart';
import '../features/profile/edit_profile_screen.dart';
import '../features/profile/profile_screen.dart';
import '../features/portal/portal_billing_screen.dart';
import '../features/portal/portal_home_screen.dart';
import '../features/portal/portal_profile_screen.dart';
import '../features/portal/portal_requests_screen.dart';
import '../features/portal/portal_tickets_screen.dart';
import 'nav_registry.dart';
import 'not_authorized_screen.dart';
import 'portal_shell.dart';
import 'shell.dart';
import 'splash_screen.dart';

/// Route names, so no screen has to spell a path out.
abstract final class Routes {
  static const splash = '/splash';
  static const login = '/login';
  static const forgotPassword = '/forgot-password';
  static const register = '/register';
  static const verifyEmail = '/verify-email';

  static const home = '/';
  static const attendance = '/attendance';
  static const leave = '/leave';
  static const alerts = '/alerts';
  static const profile = '/me';

  static const payslips = '/payslips';
  static const requests = '/requests';
  static const support = '/support';
  static const crm = '/crm';
  static const finance = '/finance';
  static const platform = '/platform';
  static const directory = '/people';
  static const itam = '/assets';
  static const recruitment = '/hiring';
  static const performance = '/performance';
  static const search = '/search';
  static const ai = '/ai';
  static const kb = '/kb';
  static const admin = '/setup';
  static const users = '/users';
  static const careerPage = '/hiring/career-page';
  static const recruitmentReports = '/hiring/reports';
  static const catalogue = '/catalogue';
  static const supportAdmin = '/support-desk';
  static const workflows = '/workflows';
  static const biometric = '/terminals';
  static const payroll = '/payroll';
  static const salary = '/pay';
  static const accounting = '/books';
  static const reconciliation = '/against-the-bank';
  static const entitlements = '/entitlements';
  static const company = '/your-company';
  static const reports = '/reports';
  static const payables = '/payables';
  static const receivables = '/receipts';
  static const closing = '/month-end';
  static const budgets = '/finance/budgets';
  static const platformLocations = '/platform/locations';
  static const crmReports = '/crm/reports';
  static const shiftRoster = '/attendance/shift-assignments';
  static const salarySheet = '/hrm/salary-sheet';
  static const subscriptionPlan = '/subscription-plan';
  static const plans = '/platform/plans';
  static const hrPolicy = '/hr-rules';
  static const contacts = '/contacts';
  static const teamAttendance = '/who-is-in';
  static const supportQueue = '/queue';
  static const kbAuthoring = '/articles';
  static const reviews = '/reviews';
  static const aiDrafts = '/drafting';
  static const aiSettings = '/assistant-settings';
  static const dashboard = '/how-things-stand';
  static const platformDashboard = '/the-platform';
  static const appearance = '/me/appearance';
  static const editProfile = '/me/edit';
  static const changePassword = '/me/password';
  static const changeEmail = '/me/email';
  static const notificationPreferences = '/me/notifications';
  static const notAuthorized = '/not-authorized';
  static const approvals = '/approvals';
}

/// The client portal's own routes.
///
/// Kept under one prefix so the redirect can tell the two apps apart by path
/// alone: everything under `/client` belongs to a portal client, everything
/// else to staff.
abstract final class PortalRoutes {
  static const prefix = '/client';

  static const home = '/client';
  static const requests = '/client/requests';
  static const billing = '/client/billing';
  static const help = '/client/help';
  static const account = '/client/account';
}

/// Bridges the auth provider to GoRouter, which wants a [Listenable].
class _AuthRefresh extends ChangeNotifier {
  void ping() => notifyListeners();
}

final _routerRefreshProvider = Provider<_AuthRefresh>((ref) {
  final refresh = _AuthRefresh();
  ref.onDispose(refresh.dispose);
  return refresh;
});

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ref.watch(_routerRefreshProvider);

  // Signing in or out has to re-run the redirect below, otherwise the user
  // stays on the login screen after a successful sign-in.
  ref.listen(authControllerProvider, (_, _) => refresh.ping());

  return GoRouter(
    initialLocation: Routes.splash,
    refreshListenable: refresh,
    redirect: (context, state) {
      final auth = ref.read(authControllerProvider);
      final location = state.matchedLocation;

      final atSplash = location == Routes.splash;
      final atAuth = location == Routes.login ||
          location.startsWith(Routes.forgotPassword) ||
          location.startsWith(Routes.register) ||
          location.startsWith(Routes.verifyEmail);

      // Still reading the stored session. Anything else would flash a screen
      // the user may not be entitled to and then yank it away.
      if (auth.isLoading) return atSplash ? null : Routes.splash;

      final user = auth.value;
      if (user == null) return atAuth ? null : Routes.login;

      // Two apps, one binary. A CLIENT gets the portal, everyone else the
      // staff shell, and neither can wander into the other's half — a client
      // landing on the attendance tab would be shown a check-in button the
      // backend would refuse, and a staff account in the portal would hit the
      // client-scoped endpoints that 400 for them.
      final wantsPortal = user.isClient;
      final inPortal = location.startsWith(PortalRoutes.prefix);

      if (atAuth || atSplash) {
        return wantsPortal ? PortalRoutes.home : Routes.home;
      }
      if (wantsPortal && !inPortal) return PortalRoutes.home;
      if (!wantsPortal && inPortal) return Routes.home;

      // Route-level RBAC: nav-hiding alone only stops someone from tapping
      // into a screen they can't use — it does nothing for a deep link, a
      // restored back-stack entry, or a typed URL. Mirrors Angular's
      // `RoleGuard`, which blocks direct navigation the same way rather than
      // only hiding the sidebar link.
      if (!wantsPortal && location != Routes.notAuthorized) {
        final perms = ref.read(permissionControllerProvider);
        if (!isRouteAllowed(location, user, perms)) {
          return Routes.notAuthorized;
        }
      }
      return null;
    },
    routes: [
      GoRoute(
        path: Routes.splash,
        builder: (_, _) => const SplashScreen(),
      ),
      GoRoute(
        path: Routes.notAuthorized,
        builder: (_, _) => const NotAuthorizedScreen(),
      ),
      GoRoute(
        path: Routes.login,
        builder: (_, _) => const LoginScreen(),
      ),
      GoRoute(
        path: Routes.forgotPassword,
        builder: (_, _) => const ForgotPasswordScreen(),
      ),
      GoRoute(
        path: Routes.register,
        builder: (_, _) => const RegisterScreen(),
      ),
      GoRoute(
        path: Routes.verifyEmail,
        builder: (_, state) =>
            VerifyEmailScreen(initialEmail: state.extra as String?),
      ),

      // Full-screen pushes that sit above the tab bar, because each is a task
      // you finish and back out of rather than a place you dwell in.
      GoRoute(
        path: Routes.payslips,
        builder: (_, _) => const PayslipsScreen(),
      ),
      GoRoute(
        path: Routes.requests,
        builder: (_, state) =>
            RequestsScreen(initialTabLabel: state.extra as String?),
      ),
      GoRoute(
        path: Routes.approvals,
        builder: (_, _) => const ApprovalsScreen(),
      ),
      GoRoute(
        path: Routes.support,
        builder: (_, state) =>
            SupportScreen(initialTabLabel: state.extra as String?),
      ),
      GoRoute(
        path: Routes.crm,
        builder: (_, state) =>
            CrmScreen(initialTabLabel: state.extra as String?),
      ),
      GoRoute(
        path: Routes.crmReports,
        builder: (_, _) => const CrmReportsScreen(),
      ),
      GoRoute(
        path: Routes.finance,
        builder: (_, state) =>
            FinanceScreen(initialTabLabel: state.extra as String?),
      ),
      GoRoute(
        path: Routes.search,
        builder: (_, _) => const SearchScreen(),
      ),
      GoRoute(
        path: Routes.ai,
        builder: (_, _) => const AiScreen(),
      ),
      GoRoute(
        path: Routes.kb,
        builder: (_, _) => const KbScreen(),
      ),
      GoRoute(
        path: Routes.admin,
        builder: (_, state) =>
            AdminScreen(initialTabLabel: state.extra as String?),
      ),
      GoRoute(
        path: Routes.users,
        builder: (_, _) => const AccountsScreen(),
      ),
      GoRoute(
        path: Routes.catalogue,
        builder: (_, state) =>
            CatalogueScreen(initialTabLabel: state.extra as String?),
      ),
      GoRoute(
        path: Routes.supportAdmin,
        builder: (_, state) =>
            SupportAdminScreen(initialTabLabel: state.extra as String?),
      ),
      GoRoute(
        path: Routes.workflows,
        builder: (_, _) => const WorkflowScreen(),
      ),
      GoRoute(
        path: Routes.biometric,
        builder: (_, _) => const BiometricScreen(),
      ),
      GoRoute(
        path: Routes.payroll,
        builder: (_, _) => const PayrollScreen(),
      ),
      GoRoute(
        path: Routes.salarySheet,
        builder: (_, _) => const SalarySheetScreen(),
      ),
      GoRoute(
        path: Routes.salary,
        builder: (_, state) =>
            SalaryScreen(initialTabLabel: state.extra as String?),
      ),
      GoRoute(
        path: Routes.company,
        builder: (_, _) => const CompanyScreen(),
      ),
      GoRoute(
        path: Routes.subscriptionPlan,
        builder: (_, _) => const SubscriptionPlanScreen(),
      ),
      GoRoute(
        path: Routes.entitlements,
        builder: (_, _) => const EntitlementsScreen(),
      ),
      GoRoute(
        path: Routes.reconciliation,
        builder: (_, _) => const ReconciliationScreen(),
      ),
      GoRoute(
        path: Routes.accounting,
        builder: (_, state) =>
            AccountingScreen(initialTabLabel: state.extra as String?),
      ),
      GoRoute(
        path: Routes.reports,
        builder: (_, _) => const ReportsScreen(),
      ),
      GoRoute(
        path: Routes.payables,
        builder: (_, state) =>
            PayablesScreen(initialTabLabel: state.extra as String?),
      ),
      GoRoute(
        path: Routes.receivables,
        builder: (_, state) =>
            ReceivablesScreen(initialTabLabel: state.extra as String?),
      ),
      GoRoute(
        path: Routes.closing,
        builder: (_, state) =>
            ClosingScreen(initialTabLabel: state.extra as String?),
      ),
      GoRoute(
        path: Routes.budgets,
        builder: (_, _) => const BudgetScreen(),
      ),
      GoRoute(
        path: Routes.platformLocations,
        builder: (_, _) => const LocationsScreen(),
      ),
      GoRoute(
        path: Routes.hrPolicy,
        builder: (_, state) =>
            HrPolicyScreen(initialTabLabel: state.extra as String?),
      ),
      GoRoute(
        path: Routes.contacts,
        builder: (_, _) => const ContactsScreen(),
      ),
      GoRoute(
        path: Routes.teamAttendance,
        builder: (_, _) => const TeamAttendanceScreen(),
      ),
      GoRoute(
        path: Routes.shiftRoster,
        builder: (_, _) => const ShiftRosterScreen(),
      ),
      GoRoute(
        path: Routes.supportQueue,
        builder: (_, _) => const SupportQueueScreen(),
      ),
      GoRoute(
        path: Routes.kbAuthoring,
        builder: (_, _) => const KbAuthoringScreen(),
      ),
      GoRoute(
        path: Routes.reviews,
        builder: (_, _) => const ReviewsScreen(),
      ),
      GoRoute(
        path: Routes.aiDrafts,
        builder: (_, _) => const AiDraftsScreen(),
      ),
      GoRoute(
        path: Routes.aiSettings,
        builder: (_, _) => const AiSettingsScreen(),
      ),
      GoRoute(
        path: Routes.dashboard,
        builder: (_, _) => const DashboardScreen(),
      ),
      GoRoute(
        path: Routes.platformDashboard,
        builder: (_, _) => const PlatformDashboardScreen(),
      ),
      GoRoute(
        path: Routes.performance,
        builder: (_, _) => const PerformanceScreen(),
      ),
      GoRoute(
        path: Routes.recruitment,
        builder: (_, state) =>
            RecruitmentScreen(initialTabLabel: state.extra as String?),
      ),
      GoRoute(
        path: Routes.careerPage,
        builder: (_, _) => const CareerPageScreen(),
      ),
      GoRoute(
        path: Routes.recruitmentReports,
        builder: (_, _) => const RecruitmentKpiScreen(),
      ),
      GoRoute(
        path: Routes.itam,
        builder: (_, state) =>
            ItamScreen(initialTabLabel: state.extra as String?),
      ),
      GoRoute(
        path: Routes.directory,
        builder: (_, _) => const DirectoryScreen(),
      ),
      GoRoute(
        path: Routes.platform,
        builder: (_, state) =>
            PlatformScreen(initialTabLabel: state.extra as String?),
      ),
      GoRoute(
        path: Routes.plans,
        builder: (_, _) => const PlansScreen(),
      ),
      GoRoute(
        path: Routes.appearance,
        builder: (_, _) => const AppearanceScreen(),
      ),
      GoRoute(
        path: Routes.editProfile,
        builder: (_, _) => const EditProfileScreen(),
      ),
      GoRoute(
        path: Routes.changePassword,
        builder: (_, _) => const ChangePasswordScreen(),
      ),
      GoRoute(
        path: Routes.changeEmail,
        builder: (_, _) => const ChangeEmailScreen(),
      ),
      GoRoute(
        path: Routes.notificationPreferences,
        builder: (_, _) => const NotificationPreferencesScreen(),
      ),

      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            AppShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(path: Routes.home, builder: (_, _) => const HomeScreen()),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.attendance,
                builder: (_, state) =>
                    AttendanceScreen(initialTabLabel: state.extra as String?),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.leave,
                builder: (_, state) =>
                    LeaveScreen(initialTabLabel: state.extra as String?),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.alerts,
                builder: (_, _) => const AlertsScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.profile,
                builder: (_, _) => const ProfileScreen(),
              ),
            ],
          ),
        ],
      ),

      // The client portal: its own shell, its own five tabs, reached only by a
      // CLIENT. Kept as a sibling of the staff shell rather than a mode inside
      // it, so neither app's navigation has to know the other exists.
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            PortalShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: PortalRoutes.home,
                builder: (_, _) => const PortalHomeScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: PortalRoutes.requests,
                builder: (_, _) => const PortalRequestsScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: PortalRoutes.billing,
                builder: (_, _) => const PortalBillingScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: PortalRoutes.help,
                builder: (_, _) => const PortalTicketsScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: PortalRoutes.account,
                builder: (_, _) => const PortalProfileScreen(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
});
