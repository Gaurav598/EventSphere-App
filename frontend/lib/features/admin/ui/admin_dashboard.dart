import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:frontend/features/admin/providers/admin_provider.dart';
import 'package:frontend/features/auth/providers/auth_provider.dart';
import 'package:frontend/shared/widgets/loading_view.dart';
import 'package:frontend/shared/widgets/error_view.dart';
import 'package:frontend/shared/widgets/empty_state_view.dart';

import 'package:frontend/core/theme_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:flutter/services.dart';
import 'package:frontend/shared/widgets/animated_confirm_dialog.dart';
import 'package:frontend/shared/widgets/animated_toast.dart';

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  final _searchController = TextEditingController();
  String _selectedFilter = 'All';
  final List<String> _filters = ['All', 'Upcoming', 'Private', 'Public'];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AdminProvider>().fetchMyEvents();
      context.read<AdminProvider>().fetchAnalytics();
    });
  }

  @override
  Widget build(BuildContext context) {
    final adminProvider = context.watch<AdminProvider>();
    final authProvider = context.watch<AuthProvider>();
    final themeProvider = context.watch<ThemeProvider>();

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Admin Dashboard'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'My Events', icon: Icon(Icons.event)),
              Tab(text: 'Analytics', icon: Icon(Icons.analytics)),
            ],
          ),
          actions: [
            IconButton(
              icon: Icon(themeProvider.isDarkMode ? Icons.light_mode : Icons.dark_mode),
              onPressed: () => themeProvider.toggleTheme(),
            ),
            IconButton(
              icon: const Icon(Icons.person),
              onPressed: () => context.push('/profile'),
            ),
            IconButton(
              icon: const Icon(Icons.logout),
              onPressed: () async {
                final confirm = await AnimatedConfirmDialog.show(
                  context,
                  title: 'Logout',
                  message: 'Are you sure you want to logout?',
                  icon: Icons.logout,
                  color: Theme.of(context).colorScheme.error,
                );
                if (confirm && context.mounted) {
                  authProvider.logout();
                  context.go('/login');
                }
              },
            ),
          ],
        ),
        body: TabBarView(
          children: [
            _buildEventsTab(adminProvider),
            _buildAnalyticsTab(adminProvider),
          ],
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: () => context.push('/admin/create-event'),
          child: const Icon(Icons.add),
        ),
      ),
    );
  }

  Widget _buildEventsTab(AdminProvider adminProvider) {
    if (adminProvider.isLoading) return const LoadingView();
    if (adminProvider.error != null) {
      return ErrorView(
        message: adminProvider.error!,
        onRetry: () => adminProvider.fetchMyEvents(),
      );
    }
    if (adminProvider.myEvents.isEmpty) {
      return const EmptyStateView(message: 'You have not created any events.',
        icon: Icons.event_note,
      );
    }
    
    var filteredEvents = adminProvider.myEvents.toList();
    if (_searchController.text.isNotEmpty) {
      final query = _searchController.text.toLowerCase();
      filteredEvents = filteredEvents.where((e) => e.name.toLowerCase().contains(query)).toList();
    }
    if (_selectedFilter == 'Upcoming') {
      filteredEvents = filteredEvents.where((e) => e.eventDate.isAfter(DateTime.now())).toList();
    } else if (_selectedFilter == 'Private') {
      filteredEvents = filteredEvents.where((e) => e.isPrivate).toList();
    } else if (_selectedFilter == 'Public') {
      filteredEvents = filteredEvents.where((e) => !e.isPrivate).toList();
    }
    
    return RefreshIndicator(
      onRefresh: () => adminProvider.fetchMyEvents(),
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Search my events...',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () => setState(() => _searchController.clear()),
                            )
                          : null,
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 40,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: _filters.length,
                      itemBuilder: (context, index) {
                        final filter = _filters[index];
                        final isSelected = _selectedFilter == filter;
                        return Padding(
                          padding: const EdgeInsets.only(right: 8.0),
                          child: FilterChip(
                            label: Text(filter),
                            selected: isSelected,
                            onSelected: (selected) => setState(() => _selectedFilter = filter),
                            selectedColor: Theme.of(context).colorScheme.primary.withOpacity(0.2),
                            checkmarkColor: Theme.of(context).colorScheme.primary,
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (filteredEvents.isEmpty)
            const SliverFillRemaining(
              child: EmptyStateView(message: 'No events match your filters.', icon: Icons.filter_list_off),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final event = filteredEvents[index];
                    final theme = Theme.of(context);
                    return Card(
            clipBehavior: Clip.antiAlias,
            margin: const EdgeInsets.only(bottom: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Banner
                Container(
                  height: 100,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withOpacity(0.1),
                    image: const DecorationImage(
                      image: AssetImage('assets/images/auth_bg.png'),
                      fit: BoxFit.cover,
                      colorFilter: ColorFilter.mode(Colors.black54, BlendMode.darken),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                event.name,
                                style: theme.textTheme.titleLarge?.copyWith(color: Colors.white, fontWeight: FontWeight.bold),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: event.isRegistrationOpen ? Colors.green : Colors.red,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                event.isRegistrationOpen ? 'OPEN' : 'CLOSED',
                                style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Capacity', style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey)),
                          const SizedBox(height: 4),
                          Text('${event.registeredCount} / ${event.capacity}', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                        ],
                      ),
                      if (event.isPrivate)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceVariant,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Row(
                            children: [
                              Icon(Icons.lock, size: 16),
                              SizedBox(width: 4),
                              Text('Private', style: TextStyle(fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                Divider(height: 1, color: theme.dividerColor),
                OverflowBar(
                  alignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    TextButton.icon(
                      icon: const Icon(Icons.edit, size: 18),
                      label: const Text('Edit'),
                      onPressed: () => context.push('/admin/events/${event.id}/edit', extra: event),
                    ),
                    TextButton.icon(
                      icon: const Icon(Icons.people, size: 18),
                      label: const Text('Attendees'),
                      onPressed: () => context.push('/admin/events/${event.id}/registrations', extra: event),
                    ),
                    if (event.isRegistrationOpen)
                      TextButton.icon(
                        icon: const Icon(Icons.block, size: 18, color: Colors.orange),
                        label: const Text('Close', style: TextStyle(color: Colors.orange)),
                        onPressed: () => adminProvider.closeRegistration(event.id),
                      ),
                    if (event.isPrivate && event.inviteCode != null)
                      TextButton.icon(
                        icon: const Icon(Icons.share, size: 18, color: Colors.blue),
                        label: const Text('Share', style: TextStyle(color: Colors.blue)),
                        onPressed: () => _showShareDialog(context, event.inviteCode!),
                      ),
                    TextButton.icon(
                      icon: const Icon(Icons.delete, size: 18, color: Colors.red),
                      label: const Text('Delete', style: TextStyle(color: Colors.red)),
                      onPressed: () => _deleteEvent(context, event.id),
                    ),
                  ],
                )
              ],
            ),
          );
                  },
                  childCount: filteredEvents.length,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildAnalyticsTab(AdminProvider adminProvider) {
    if (adminProvider.isAnalyticsLoading) return const LoadingView();
    if (adminProvider.analyticsError != null) {
      return ErrorView(
        message: adminProvider.analyticsError!,
        onRetry: () => adminProvider.fetchAnalytics(),
      );
    }
    if (adminProvider.analyticsSummary == null) {
      return const EmptyStateView(message: 'No analytics available', icon: Icons.bar_chart);
    }

    final summary = adminProvider.analyticsSummary!;
    final theme = Theme.of(context);
    
    return RefreshIndicator(
      onRefresh: () => adminProvider.fetchAnalytics(),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 16,
            crossAxisSpacing: 16,
            childAspectRatio: 1.2,
            children: [
              _buildStatCard('Confirmed', summary['confirmedRegistrations'].toString(), Icons.check_circle, Colors.green),
              _buildStatCard('Checked in', summary['checkedInRegistrations'].toString(), Icons.how_to_reg, Colors.teal),
              _buildStatCard('Pending', summary['pendingRegistrations'].toString(), Icons.hourglass_empty, Colors.orange),
              _buildStatCard('Waitlisted', summary['waitlistedRegistrations'].toString(), Icons.queue, Colors.amber.shade800),
              _buildStatCard('Rejected', summary['rejectedRegistrations'].toString(), Icons.cancel, Colors.red),
              _buildStatCard('Cancelled', summary['cancelledRegistrations'].toString(), Icons.event_busy, Colors.redAccent),
              _buildStatCard('Total Requests', summary['totalRequests'].toString(), Icons.group, theme.colorScheme.primary),
              _buildStatCard('Acceptance', '${summary['acceptanceRate']}%', Icons.analytics, Colors.blue),
            ],
          ),
          const SizedBox(height: 32),
          Text('Top Performing Events', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          ...adminProvider.topEvents.map((e) {
            final evt = e['event'] as Map<String, dynamic>;
            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: theme.colorScheme.primary.withOpacity(0.2),
                  child: Icon(Icons.star, color: theme.colorScheme.primary),
                ),
                title: Text(evt['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold)),
                trailing: Chip(
                  label: Text('${e['totalRegistrations']} reg'),
                  backgroundColor: theme.colorScheme.surfaceVariant,
                ),
              ),
            );
          }),
          const SizedBox(height: 32),
          Text('Registrations by Category', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          ...adminProvider.categoryWise.map((c) => Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              leading: Icon(Icons.category, color: theme.colorScheme.secondary),
              title: Text(c['category'] ?? 'Unknown', style: const TextStyle(fontWeight: FontWeight.bold)),
              trailing: Text(c['count'].toString(), style: theme.textTheme.titleMedium),
            ),
          )),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color) {
    return Card(
      elevation: 0,
      color: color.withOpacity(0.1),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: color.withOpacity(0.3), width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            Icon(icon, size: 28, color: color),
            const SizedBox(height: 8),
            Text(value, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: color)),
            const SizedBox(height: 2),
            Text(title, textAlign: TextAlign.center, style: TextStyle(color: color.withOpacity(0.8), fontSize: 12, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteEvent(BuildContext context, String eventId) async {
    final confirm = await AnimatedConfirmDialog.show(
      context,
      title: 'Delete Event',
      message: 'Are you sure you want to delete this event? This action cannot be undone.',
      icon: Icons.delete_outline,
      color: Colors.red,
      confirmText: 'DELETE',
    );
    if (confirm && context.mounted) {
      context.read<AdminProvider>().deleteEvent(eventId);
    }
  }

  void _showShareDialog(BuildContext context, String inviteCode) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Invite Attendees', textAlign: TextAlign.center),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Share this QR code or the invite code below.'),
            const SizedBox(height: 16),
            SizedBox(
              width: 200,
              height: 200,
              child: QrImageView(
                data: inviteCode,
                version: QrVersions.auto,
                backgroundColor: Colors.white,
              ),
            ),
            const SizedBox(height: 16),
            SelectableText(
              inviteCode,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, letterSpacing: 2),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('CLOSE'),
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.copy),
            label: const Text('COPY CODE'),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: inviteCode));
              if (context.mounted) {
                AnimatedToast.show(context, message: 'Invite code copied to clipboard!', isError: false);
              }
              Navigator.of(ctx).pop();
            },
          ),
        ],
      ),
    );
  }
}
