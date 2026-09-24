import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:frontend/features/tickets/models/ticket.dart';
import 'package:frontend/features/tickets/providers/ticket_provider.dart';
import 'package:frontend/shared/widgets/error_view.dart';
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

  @override
  void initState() {
    super.initState();
    _ticket = widget.ticket.canDisplayTicket ? widget.ticket : null;
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final provider = context.read<TicketProvider>();
    final result = await provider.loadIssuedTicket(widget.ticket);
    if (!mounted) return;
    setState(() {
      _ticket = result;
      _error = result == null ? provider.error : null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<TicketProvider>();
    if (provider.isLoading && _ticket == null) {
      return Scaffold(appBar: AppBar(title: const Text('Ticket')), body: const LoadingView());
    }
    if (_ticket == null || _ticket!.qrPayload == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Ticket')),
        body: ErrorView(message: _error ?? 'Ticket is not ready yet.', onRetry: _load),
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
}
