import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:frontend/features/tickets/models/ticket.dart';
import 'package:frontend/features/tickets/providers/ticket_provider.dart';
import 'package:frontend/shared/widgets/loading_view.dart';

class TicketDetailsScreen extends StatefulWidget {
  final Ticket ticket;

  const TicketDetailsScreen({super.key, required this.ticket});

  @override
  State<TicketDetailsScreen> createState() => _TicketDetailsScreenState();
}

class _TicketDetailsScreenState extends State<TicketDetailsScreen> {
  Ticket? _ticket;
  String? _error;
  bool _isOffline = false;

  @override
  void initState() {
    super.initState();
    _ticket = widget.ticket.canDisplayTicket ? widget.ticket : null;
    if (const {'confirmed', 'checked_in'}.contains(widget.ticket.status)) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    }
  }

  Future<void> _load() async {
    final provider = context.read<TicketProvider>();
    final result = await provider.loadIssuedTicket(widget.ticket);
    if (!mounted) return;
    setState(() {
      _ticket = result;
      _error = result == null ? provider.error : null;
      _isOffline = result != null && (provider.error?.startsWith('Showing a downloaded ticket offline') ?? false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<TicketProvider>();
    if (!const {'confirmed', 'checked_in'}.contains(widget.ticket.status)) {
      return _registrationDetails(context, widget.ticket);
    }
    if (provider.isLoading && _ticket == null) {
      return Scaffold(appBar: AppBar(title: const Text('Ticket')), body: const LoadingView());
    }
    if (_ticket == null || _ticket!.qrPayload == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Ticket')),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.qr_code_2, size: 64),
                  const SizedBox(height: 16),
                  Text('Ticket ${widget.ticket.ticketStatus}', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 8),
                  Text(_error ?? 'Ticket generation is still in progress.', textAlign: TextAlign.center),
                  const SizedBox(height: 20),
                  FilledButton.icon(icon: const Icon(Icons.refresh), label: const Text('Refresh'), onPressed: _load),
                  if (widget.ticket.ticketStatus == 'FAILED' || widget.ticket.ticketStatus == 'RETRYABLE')
                    TextButton(
                      onPressed: () async {
                        await context.read<TicketProvider>().retryTicket(widget.ticket.id);
                        if (mounted) await _load();
                      },
                      child: const Text('Retry ticket generation'),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
    }
    final ticket = _ticket!;
    return Scaffold(
      appBar: AppBar(title: const Text('Ticket')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Semantics(
            label: 'QR event ticket for ${ticket.event?.name ?? 'event'}',
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(ticket.event?.name ?? 'Event ticket', style: Theme.of(context).textTheme.headlineSmall, textAlign: TextAlign.center),
                    const SizedBox(height: 8),
                    Text(ticket.status.replaceAll('_', ' ').toUpperCase()),
                    if (_isOffline) ...[
                      const SizedBox(height: 12),
                      const Card(
                        color: Colors.amberAccent,
                        child: Padding(
                          padding: EdgeInsets.all(10),
                          child: Text('Offline copy — entry remains subject to online server validation.', textAlign: TextAlign.center),
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                    Container(
                      padding: const EdgeInsets.all(16),
                      color: Colors.white,
                      child: QrImageView(data: ticket.qrPayload!, version: QrVersions.auto, size: 240),
                    ),
                    const SizedBox(height: 20),
                    const Text('This downloaded QR can be displayed offline. Admission is authoritative only after the organizer validates it online.', textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    SelectableText('Registration ${ticket.id}', style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _registrationDetails(BuildContext context, Ticket registration) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Registration details')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Icon(
                registration.status == 'pending'
                    ? Icons.hourglass_top
                    : registration.status == 'waitlisted'
                        ? Icons.queue
                        : registration.status == 'rejected'
                            ? Icons.cancel_outlined
                            : Icons.event_busy,
                size: 64,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: 20),
              Text(registration.event?.name ?? 'Event registration', style: theme.textTheme.headlineSmall, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              Text(registration.status.replaceAll('_', ' ').toUpperCase(), style: theme.textTheme.titleMedium, textAlign: TextAlign.center),
              if (registration.status == 'pending')
                const Padding(padding: EdgeInsets.only(top: 12), child: Text('Your request is waiting for organizer approval.', textAlign: TextAlign.center)),
              if (registration.status == 'waitlisted')
                Padding(padding: const EdgeInsets.only(top: 12), child: Text('Waitlist position: ${registration.waitlistPosition ?? '—'}', textAlign: TextAlign.center)),
              if (registration.status == 'rejected')
                const Padding(padding: EdgeInsets.only(top: 12), child: Text('The organizer did not approve this request.', textAlign: TextAlign.center)),
              if (registration.status == 'cancelled')
                const Padding(padding: EdgeInsets.only(top: 12), child: Text('This registration is cancelled and any issued ticket is no longer valid.', textAlign: TextAlign.center)),
              const SizedBox(height: 24),
              if (registration.canCancel)
                OutlinedButton.icon(
                  icon: const Icon(Icons.event_busy),
                  label: const Text('Cancel registration'),
                  onPressed: () async {
                    final success = await context.read<TicketProvider>().cancel(registration.id);
                    if (success && context.mounted) Navigator.of(context).pop();
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}
