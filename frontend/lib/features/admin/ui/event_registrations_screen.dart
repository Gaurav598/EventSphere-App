import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:frontend/features/admin/providers/admin_provider.dart';
import 'package:frontend/features/events/models/event.dart';
import 'package:frontend/shared/widgets/animated_confirm_dialog.dart';
import 'package:frontend/shared/widgets/animated_toast.dart';
import 'package:frontend/shared/widgets/empty_state_view.dart';
import 'package:frontend/shared/widgets/error_view.dart';
import 'package:frontend/shared/widgets/loading_view.dart';

class EventRegistrationsScreen extends StatefulWidget {
  final Event event;

  const EventRegistrationsScreen({super.key, required this.event});

  @override
  State<EventRegistrationsScreen> createState() => _EventRegistrationsScreenState();
}

class _EventRegistrationsScreenState extends State<EventRegistrationsScreen> {
  List<Map<String, dynamic>> _registrations = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadRegistrations();
  }

  Future<void> _loadRegistrations() async {
    if (mounted) setState(() => _isLoading = true);
    final provider = context.read<AdminProvider>();
    final data = await provider.getEventRegistrations(widget.event.id);
    if (!mounted) return;
    setState(() {
      _registrations = data;
      _error = provider.error;
      _isLoading = false;
    });
  }

  Future<void> _exportCsv() async {
    final csvData = await context.read<AdminProvider>().exportRegistrations(widget.event.id);
    if (csvData == null || !mounted) {
      if (mounted) AnimatedToast.show(context, message: 'Failed to export registrations', isError: true);
      return;
    }
    if (kIsWeb) {
      final uri = Uri.parse('data:text/csv;charset=utf-8,${Uri.encodeComponent(csvData)}');
      if (!await launchUrl(uri) && mounted) {
        AnimatedToast.show(context, message: 'Could not open CSV export', isError: true);
      }
      return;
    }
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/registrations_${widget.event.id}.csv');
      await file.writeAsString(csvData);
      if (!mounted) return;
      final box = context.findRenderObject() as RenderBox?;
      await Share.shareXFiles(
        [XFile(file.path)],
        subject: '${widget.event.name} registrations',
        sharePositionOrigin: box == null ? null : box.localToGlobal(Offset.zero) & box.size,
      );
    } catch (error) {
      if (mounted) AnimatedToast.show(context, message: 'Failed to save CSV: $error', isError: true);
    }
  }

  Future<void> _updateStatus(Map<String, dynamic> registration, String status) async {
    final provider = context.read<AdminProvider>();
    final success = await provider.updateRegistrationStatus(registration['registrationId'], status);
    if (!mounted) return;
    if (success) {
      await _loadRegistrations();
      if (mounted) AnimatedToast.show(context, message: 'Registration ${status.replaceAll('_', ' ')}', isError: false);
    } else {
      AnimatedToast.show(context, message: provider.error ?? 'Status update failed', isError: true);
    }
  }

  Future<void> _cancel(Map<String, dynamic> registration) async {
    final confirmed = await AnimatedConfirmDialog.show(
      context,
      title: 'Cancel registration',
      message: 'Release this attendee’s seat? The next waitlisted attendee may be promoted automatically.',
      icon: Icons.person_remove_outlined,
      color: Colors.red,
      confirmText: 'CANCEL REGISTRATION',
    );
    if (confirmed && mounted) await _updateStatus(registration, 'cancelled');
  }

  List<Map<String, dynamic>> _withStatus(Set<String> statuses) =>
      _registrations.where((item) => statuses.contains(item['status'])).toList();

  @override
  Widget build(BuildContext context) {
    final title = '${widget.event.name} registrations';
    if (_isLoading) return Scaffold(appBar: AppBar(title: Text(title)), body: const LoadingView());
    if (_error != null && _registrations.isEmpty) {
      return Scaffold(appBar: AppBar(title: Text(title)), body: ErrorView(message: _error!, onRetry: _loadRegistrations));
    }

    final groups = <({String label, Set<String> statuses})>[
      (label: 'Pending', statuses: {'pending'}),
      (label: 'Confirmed', statuses: {'confirmed'}),
      (label: 'Checked in', statuses: {'checked_in'}),
      (label: 'Waitlist', statuses: {'waitlisted'}),
      (label: 'History', statuses: {'rejected', 'cancelled'}),
    ];

    return DefaultTabController(
      length: groups.length,
      child: Scaffold(
        appBar: AppBar(
          title: Text(title),
          actions: [
            IconButton(
              icon: const Icon(Icons.qr_code_scanner),
              tooltip: 'Scan signed ticket',
              onPressed: () => context.push('/admin/events/${widget.event.id}/scan'),
            ),
            IconButton(icon: const Icon(Icons.download), tooltip: 'Export CSV', onPressed: _exportCsv),
          ],
          bottom: TabBar(
            isScrollable: true,
            tabs: [
              for (final group in groups)
                Tab(text: '${group.label} (${_withStatus(group.statuses).length})'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            for (final group in groups) _buildList(group.label, _withStatus(group.statuses)),
          ],
        ),
      ),
    );
  }

  Widget _buildList(String label, List<Map<String, dynamic>> registrations) {
    if (registrations.isEmpty) {
      return EmptyStateView(message: 'No ${label.toLowerCase()} registrations.', icon: Icons.group_off);
    }
    return RefreshIndicator(
      onRefresh: _loadRegistrations,
      child: ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: registrations.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          final registration = registrations[index];
          final user = Map<String, dynamic>.from(registration['user'] ?? const {});
          final status = registration['status']?.toString() ?? 'unknown';
          final ticketStatus = registration['ticketStatus']?.toString() ?? 'NOT_REQUIRED';
          return Card(
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              leading: CircleAvatar(child: Text((user['name']?.toString().isNotEmpty ?? false) ? user['name'].toString()[0].toUpperCase() : '?')),
              title: Text(user['name'] ?? 'Unknown attendee'),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(user['email'] ?? ''),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      Chip(label: Text(status.replaceAll('_', ' ').toUpperCase()), visualDensity: VisualDensity.compact),
                      if (status == 'confirmed') Chip(label: Text('TICKET $ticketStatus'), visualDensity: VisualDensity.compact),
                      if (status == 'waitlisted' && registration['waitlistSequence'] != null)
                        Chip(label: Text('QUEUE ${registration['waitlistSequence']}'), visualDensity: VisualDensity.compact),
                    ],
                  ),
                ],
              ),
              trailing: status == 'pending'
                  ? Wrap(
                      spacing: 4,
                      children: [
                        IconButton(icon: const Icon(Icons.check, color: Colors.green), tooltip: 'Approve', onPressed: () => _updateStatus(registration, 'confirmed')),
                        IconButton(icon: const Icon(Icons.close, color: Colors.red), tooltip: 'Reject', onPressed: () => _updateStatus(registration, 'rejected')),
                      ],
                    )
                  : {'confirmed', 'waitlisted'}.contains(status)
                      ? IconButton(icon: const Icon(Icons.person_remove_outlined, color: Colors.red), tooltip: 'Cancel registration', onPressed: () => _cancel(registration))
                      : null,
            ),
          );
        },
      ),
    );
  }
}
