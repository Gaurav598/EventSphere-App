import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:frontend/features/tickets/models/ticket.dart';
import 'package:frontend/features/tickets/providers/ticket_provider.dart';
import 'package:frontend/shared/widgets/animated_confirm_dialog.dart';
import 'package:frontend/shared/widgets/animated_toast.dart';
import 'package:frontend/shared/widgets/empty_state_view.dart';
import 'package:frontend/shared/widgets/error_view.dart';
import 'package:frontend/shared/widgets/loading_view.dart';

class MyTicketsScreen extends StatefulWidget {
  const MyTicketsScreen({super.key});

  @override
  State<MyTicketsScreen> createState() => _MyTicketsScreenState();
}

class _MyTicketsScreenState extends State<MyTicketsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<TicketProvider>().fetchMyTickets();
    });
  }

  Color _statusColor(String status) => switch (status) {
        'confirmed' || 'checked_in' => Colors.green,
        'pending' || 'waitlisted' => Colors.orange,
        'rejected' || 'cancelled' => Colors.red,
        _ => Colors.grey,
      };

  Future<void> _cancel(Ticket ticket) async {
    final confirmed = await AnimatedConfirmDialog.show(
      context,
      title: 'Cancel registration',
      message: 'Release your place for ${ticket.event?.name ?? 'this event'}?',
      icon: Icons.event_busy,
      color: Colors.red,
      confirmText: 'CANCEL REGISTRATION',
    );
    if (!confirmed || !mounted) return;
    final provider = context.read<TicketProvider>();
    final success = await provider.cancel(ticket.id);
    if (!mounted) return;
    AnimatedToast.show(
      context,
      message: success ? 'Registration cancelled' : provider.error ?? 'Cancellation failed',
      isError: !success,
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<TicketProvider>();
    return Scaffold(
      appBar: AppBar(title: const Text('My registrations')),
      body: provider.isLoading && provider.myTickets.isEmpty
          ? const LoadingView()
          : provider.error != null && provider.myTickets.isEmpty
              ? ErrorView(message: provider.error!, onRetry: provider.fetchMyTickets)
              : provider.myTickets.isEmpty
                  ? const EmptyStateView(
                      message: 'You have no event registrations yet.',
                      icon: Icons.confirmation_num_outlined,
                    )
                  : RefreshIndicator(
                      onRefresh: provider.fetchMyTickets,
                      child: ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: provider.myTickets.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final registration = provider.myTickets[index];
                          final color = _statusColor(registration.status);
                          final ticketReady = registration.ticketStatus == 'READY';
                          return Card(
                            child: Padding(
                              padding: const EdgeInsets.all(8),
                              child: ListTile(
                                onTap: () => context.push('/tickets/${registration.id}', extra: registration),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                title: Text(registration.event?.name ?? 'Unknown event'),
                                subtitle: Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Wrap(
                                    spacing: 8,
                                    runSpacing: 6,
                                    children: [
                                      Chip(
                                        visualDensity: VisualDensity.compact,
                                        label: Text(registration.status.replaceAll('_', ' ').toUpperCase()),
                                        labelStyle: TextStyle(color: color, fontWeight: FontWeight.bold),
                                      ),
                                      if (registration.status == 'waitlisted')
                                        Chip(label: Text('Position ${registration.waitlistPosition ?? '—'}')),
                                      if (registration.status == 'confirmed')
                                        Chip(label: Text('Ticket ${registration.ticketStatus}')),
                                    ],
                                  ),
                                ),
                                trailing: PopupMenuButton<String>(
                                  onSelected: (action) async {
                                    if (action == 'ticket') {
                                      context.push('/tickets/${registration.id}', extra: registration);
                                    } else if (action == 'cancel') {
                                      await _cancel(registration);
                                    } else if (action == 'retry') {
                                      final ok = await provider.retryTicket(registration.id);
                                      if (context.mounted) {
                                        AnimatedToast.show(context, message: ok ? 'Ticket retry queued' : provider.error ?? 'Retry failed', isError: !ok);
                                      }
                                    }
                                  },
                                  itemBuilder: (_) => [
                                    if (ticketReady || registration.status == 'confirmed' || registration.status == 'checked_in')
                                      const PopupMenuItem(value: 'ticket', child: Text('View ticket')),
                                    if (registration.ticketStatus == 'FAILED' || registration.ticketStatus == 'RETRYABLE')
                                      const PopupMenuItem(value: 'retry', child: Text('Retry ticket')),
                                    if (registration.canCancel)
                                      const PopupMenuItem(value: 'cancel', child: Text('Cancel registration')),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
    );
  }
}
