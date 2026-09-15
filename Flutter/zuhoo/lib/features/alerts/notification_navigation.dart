import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../core/network/api_exception.dart';
import '../directory/directory_repository.dart' show personProvider;
import '../directory/person_detail_screen.dart';
import '../performance/performance_repository.dart' show performanceRepositoryProvider;
import '../performance/review_detail_screen.dart';
import '../requests/request_detail_screen.dart' show openRequestDetail;
import '../support/support_controllers.dart' show ThreadKind;
import '../support/ticket_detail_screen.dart' show openTicket;
import 'notification_repository.dart';

/// Opens whatever a notification's `actionUrl` points to.
///
/// `actionUrl` is stamped by the Spring Boot side for the Angular web app's
/// own router (see `CreateNotificationRequest.forRequest`/`.of`) — paths like
/// `/crm/pipeline`, `/servicereview-requests/42`, `/hrm/performance/7`. This
/// maps the same paths onto Flutter's own routes rather than pushing them at
/// `go_router` verbatim, which would 404 since the two apps' route schemes
/// don't match. A path this build does not recognise is left alone rather
/// than guessed at — the notification is still marked read either way.
Future<void> openNotification(
  BuildContext context,
  WidgetRef ref,
  AppNotification notification,
) async {
  final link = notification.link?.trim();
  if (link == null || link.isEmpty) return;

  // A trailing numeric segment is an entity id on every pattern the backend
  // actually sends (`.../42`) — pulled once so each branch below can use it.
  final idMatch = RegExp(r'/(\d+)$').firstMatch(link);
  final id = idMatch == null ? null : int.tryParse(idMatch.group(1)!);
  final withoutId =
      idMatch == null ? link : link.substring(0, idMatch.start);

  Future<void> openWithSpinner(Future<void> Function() open) async {
    try {
      await open();
    } on ApiException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open that.')),
        );
      }
    }
  }

  switch (withoutId) {
    case '/servicereview-requests':
      if (id != null) openRequestDetail(context, id);
      return;

    case '/support/tickets':
      if (id != null) openTicket(context, id, ThreadKind.platform);
      return;

    // The client's own copy of a ticket has no id-based detail route today —
    // landing on their ticket list is honest, guessing which thread would not
    // be.
    case '/client/tickets':
      context.push(PortalRoutes.help);
      return;

    case '/performance':
    case '/hrm/performance':
      if (id != null) {
        await openWithSpinner(() async {
          final review =
              await ref.read(performanceRepositoryProvider).review(id);
          if (context.mounted) {
            ReviewDetailScreen.open(context, review: review);
          }
        });
      }
      return;

    case '/hrm/employees':
      if (id != null) {
        await openWithSpinner(() async {
          final person = await ref.read(personProvider(id).future);
          if (context.mounted) {
            PersonDetailScreen.open(context, person: person);
          }
        });
      }
      return;
  }

  // No id, or an id-less path: everything left is a plain list/tab target.
  if (!context.mounted) return;
  switch (link) {
    case '/leaves':
      context.push(Routes.leave, extra: 'Approvals');
    case '/payroll/my-payslips':
      context.push(Routes.payslips);
    case '/crm/leads':
      context.push(Routes.crm, extra: 'Leads');
    case '/crm/pipeline':
      context.push(Routes.crm, extra: 'Pipeline');
    case '/finance/invoices':
      context.push(Routes.finance, extra: 'Invoices');
    case '/finance/wallet':
      context.push(Routes.finance, extra: 'Wallet');
    case '/finance/payments':
      context.push(Routes.receivables, extra: 'Receipts');
    case '/finance/vendor-bills':
      context.push(Routes.payables, extra: 'Bills');
    case '/finance/fixed-assets':
      context.push(Routes.closing, extra: 'Fixed assets');
    case '/finance/bank-reconciliation':
      context.push(Routes.reconciliation);
    case '/itam/software':
      context.push(Routes.itam, extra: 'Software');
    case '/itam/hardware':
      context.push(Routes.itam, extra: 'Hardware');
    case '/settings/subscription':
      context.push(Routes.subscriptionPlan);
    case '/client/payments':
      context.push(PortalRoutes.billing);
    default:
    // An actionUrl this build has no mapping for yet — nothing to do beyond
    // the read-marking the tap already triggers.
  }
}
