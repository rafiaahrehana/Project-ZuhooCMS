import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/network/paged_response.dart';
import '../../shared/paged_controller.dart';
import 'support_models.dart';
import 'support_repository.dart';

/// Tickets this user raised to BusinessOS.
class MyTicketsController extends AsyncNotifier<PagedState<SupportTicket>>
    with PagedLoader<SupportTicket> {
  @override
  Future<PagedState<SupportTicket>> build() {
    ref.watch(currentUserProvider);
    return loadFirstPage();
  }

  @override
  Future<PagedResponse<SupportTicket>> fetchPage(int page) =>
      ref.read(supportRepositoryProvider).myTickets(page: page);

  /// Raises a ticket, then reloads. The backend assigns the ticket number, the
  /// SLA deadlines and the starting status, so the new row is read back rather
  /// than assembled from the form.
  Future<SupportTicket> create(CreateTicketRequest request) async {
    final created = await ref.read(supportRepositoryProvider).create(request);
    await refresh();
    return created;
  }
}

final myTicketsProvider =
    AsyncNotifierProvider<MyTicketsController, PagedState<SupportTicket>>(
  MyTicketsController.new,
);

/// The staff inbox of this company's own clients' tickets.
/// Which status the client-chat inbox is narrowed to. Null is all of them.
class ClientTicketStatusController extends Notifier<String?> {
  @override
  String? build() => null;

  void set(String? status) {
    if (state == status) return;
    state = status;
  }
}

final clientTicketStatusProvider =
    NotifierProvider<ClientTicketStatusController, String?>(
  ClientTicketStatusController.new,
);

class ClientTicketsController extends AsyncNotifier<PagedState<SupportTicket>>
    with PagedLoader<SupportTicket> {
  @override
  Future<PagedState<SupportTicket>> build() {
    ref.watch(currentUserProvider);
    // Watched, not read: choosing a status is what reloads the inbox. The
    // backend splits it by path rather than by query parameter.
    ref.watch(clientTicketStatusProvider);
    return loadFirstPage();
  }

  @override
  Future<PagedResponse<SupportTicket>> fetchPage(int page) =>
      ref.read(supportRepositoryProvider).clientTickets(
            status: ref.read(clientTicketStatusProvider),
            page: page,
          );
}

final clientTicketsProvider =
    AsyncNotifierProvider<ClientTicketsController, PagedState<SupportTicket>>(
  ClientTicketsController.new,
);

/// One ticket. Auto-disposed: status, assignee and SLA state all move while
/// you are not looking at it, so re-reading on open is the right default.
///
/// Two endpoints for the one record, chosen by who is asking.
/// `GET /tickets/{id}` is gated on the staff roles and excludes CLIENT
/// outright, so a portal client opening their own ticket has to go through
/// `/tickets/client/{id}`, which is scoped to their own account.
final ticketDetailProvider =
    FutureProvider.autoDispose.family<SupportTicket, int>(
  (ref, id) {
    final repo = ref.watch(supportRepositoryProvider);
    final isClient = ref.watch(currentUserProvider)?.isClient ?? false;
    return isClient ? repo.myClientTicket(id) : repo.byId(id);
  },
);

/// Which side of a conversation this thread is.
///
/// It selects the endpoint, and the two are not interchangeable: the client
/// thread is external-only, the platform thread is everything this user may
/// see. Passing the wrong one either hides half the conversation or shows a
/// client's counterpart an internal note.
enum ThreadKind { platform, clientChat }

typedef ThreadKey = ({int ticketId, ThreadKind kind});

final ticketMessagesProvider =
    FutureProvider.autoDispose.family<List<SupportMessage>, ThreadKey>(
  (ref, key) {
    final repo = ref.watch(supportRepositoryProvider);
    return switch (key.kind) {
      ThreadKind.platform => repo.messages(key.ticketId),
      ThreadKind.clientChat => repo.clientChatMessages(key.ticketId),
    };
  },
);
