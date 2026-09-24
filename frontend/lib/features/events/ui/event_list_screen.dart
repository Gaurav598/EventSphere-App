import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:frontend/features/events/providers/event_provider.dart';
import 'package:frontend/features/auth/providers/auth_provider.dart';
import 'package:frontend/shared/widgets/loading_view.dart';
import 'package:frontend/shared/widgets/error_view.dart';
import 'package:frontend/shared/widgets/empty_state_view.dart';
import 'package:frontend/shared/widgets/animated_confirm_dialog.dart';
import 'package:frontend/shared/widgets/animated_toast.dart';
import 'package:frontend/shared/widgets/event_card.dart';
import 'package:frontend/core/theme_provider.dart';

class EventListScreen extends StatefulWidget {
  const EventListScreen({super.key});

  @override
  State<EventListScreen> createState() => _EventListScreenState();
}

class _EventListScreenState extends State<EventListScreen> {
  final _searchController = TextEditingController();
  String _selectedCategory = 'All';
  final List<String> _categories = ['All', 'Conference', 'Workshop', 'Meetup', 'Social', 'Other'];
  DateTime? _dateFrom;
  DateTime? _dateTo;
  bool _favoritesOnly = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<EventProvider>().fetchEvents();
      context.read<EventProvider>().fetchFavorites();
    });
  }

  Future<void> _refreshEvents() async {
    await context.read<EventProvider>().fetchEvents(
      category: _selectedCategory == 'All' ? null : _selectedCategory.toLowerCase(),
      dateFrom: _dateFrom,
      dateTo: _dateTo,
    );
  }

  @override
  Widget build(BuildContext context) {
    final eventProvider = context.watch<EventProvider>();
    final authProvider = context.watch<AuthProvider>();
    final themeProvider = context.watch<ThemeProvider>();
    final theme = Theme.of(context);
    final visibleEvents = _favoritesOnly
        ? eventProvider.events.where((event) => eventProvider.isFavorite(event.id)).toList()
        : eventProvider.events;
    
    final user = authProvider.user;
    final userName = user?.name.split(' ').first ?? 'Guest';

    return Scaffold(
      appBar: AppBar(
        title: const Text('EventSphere'),
        actions: [
          IconButton(
            icon: Icon(_favoritesOnly ? Icons.bookmark : Icons.bookmark_border),
            tooltip: _favoritesOnly ? 'Show all events' : 'Show favorites',
            onPressed: () => setState(() => _favoritesOnly = !_favoritesOnly),
          ),
          IconButton(
            icon: const Icon(Icons.vpn_key),
            tooltip: 'Join Private Event',
            onPressed: () => _showJoinPrivateDialog(context),
          ),
          IconButton(
            icon: const Icon(Icons.confirmation_num),
            onPressed: () => context.push('/tickets'),
          ),
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
                color: theme.colorScheme.error,
              );
              if (confirm && context.mounted) {
                authProvider.logout();
                context.go('/login');
              }
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refreshEvents,
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Hello, $userName! 👋', style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Text('Find events that match your interests', style: theme.textTheme.bodyLarge),
                    const SizedBox(height: 24),

                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.date_range),
                            label: Text(_dateFrom == null ? 'Any date' : '${_dateFrom!.day}/${_dateFrom!.month}/${_dateFrom!.year} onward'),
                            onPressed: () async {
                              final picked = await showDatePicker(
                                context: context,
                                initialDate: _dateFrom ?? DateTime.now(),
                                firstDate: DateTime.now(),
                                lastDate: DateTime.now().add(const Duration(days: 730)),
                              );
                              if (picked != null) {
                                setState(() {
                                  _dateFrom = picked;
                                  _dateTo = picked.add(const Duration(days: 1));
                                });
                                _refreshEvents();
                              }
                            },
                          ),
                        ),
                        if (_dateFrom != null)
                          IconButton(
                            tooltip: 'Clear date filter',
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              setState(() {
                                _dateFrom = null;
                                _dateTo = null;
                              });
                              _refreshEvents();
                            },
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    
                    // Search Bar
                    TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: 'Search events...',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: _searchController.text.isNotEmpty ? IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _searchController.clear();
                            eventProvider.fetchEvents();
                            setState(() {});
                          },
                        ) : null,
                      ),
                      onChanged: (_) => setState(() {}),
                      onSubmitted: (query) => eventProvider.searchEvents(query),
                    ),
                    const SizedBox(height: 24),
                    
                    // Category Filters
                    SizedBox(
                      height: 40,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: _categories.length,
                        itemBuilder: (context, index) {
                          final category = _categories[index];
                          final isSelected = _selectedCategory == category;
                          return Padding(
                            padding: const EdgeInsets.only(right: 8.0),
                            child: FilterChip(
                              label: Text(category),
                              selected: isSelected,
                              onSelected: (selected) {
                                setState(() => _selectedCategory = category);
                                _refreshEvents();
                              },
                              selectedColor: theme.colorScheme.primary.withOpacity(0.2),
                              checkmarkColor: theme.colorScheme.primary,
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 24),
                    
                    Text('Upcoming Events', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
            
            // Events List
            if (eventProvider.isLoading)
              const SliverFillRemaining(child: LoadingView())
            else if (eventProvider.error != null)
              SliverFillRemaining(
                child: ErrorView(
                  message: eventProvider.error!,
                  onRetry: _refreshEvents,
                ),
              )
            else if (visibleEvents.isEmpty)
              const SliverFillRemaining(
                child: EmptyStateView(message: 'No events found for this category or search.',
                  icon: Icons.event_busy,
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final event = visibleEvents[index];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 16.0),
                        child: EventCard(
                          event: event,
                          onTap: () => context.push('/events/${event.id}'),
                        ),
                      );
                    },
                    childCount: visibleEvents.length,
                  ),
                ),
              ),
            if (!_favoritesOnly && eventProvider.pagination != null && eventProvider.pagination!.totalPages > 1)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        tooltip: 'Previous page',
                        onPressed: eventProvider.pagination!.page > 1
                            ? () => context.read<EventProvider>().fetchEvents(
                                  page: eventProvider.pagination!.page - 1,
                                  category: _selectedCategory == 'All' ? null : _selectedCategory.toLowerCase(),
                                  dateFrom: _dateFrom,
                                  dateTo: _dateTo,
                                )
                            : null,
                        icon: const Icon(Icons.chevron_left),
                      ),
                      Text('Page ${eventProvider.pagination!.page} of ${eventProvider.pagination!.totalPages}'),
                      IconButton(
                        tooltip: 'Next page',
                        onPressed: eventProvider.pagination!.page < eventProvider.pagination!.totalPages
                            ? () => context.read<EventProvider>().fetchEvents(
                                  page: eventProvider.pagination!.page + 1,
                                  category: _selectedCategory == 'All' ? null : _selectedCategory.toLowerCase(),
                                  dateFrom: _dateFrom,
                                  dateTo: _dateTo,
                                )
                            : null,
                        icon: const Icon(Icons.chevron_right),
                      ),
                    ],
                  ),
                ),
              ),
              
            const SliverPadding(padding: EdgeInsets.only(bottom: 32)),
          ],
        ),
      ),
    );
  }

  void _showJoinPrivateDialog(BuildContext context) {
    final codeController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Join Private Event'),
        content: TextField(
          controller: codeController,
          decoration: const InputDecoration(
            hintText: 'Enter Invite Code (e.g. PRV-A1B2)',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('CANCEL'),
          ),
          ElevatedButton(
            onPressed: () async {
              final code = codeController.text.trim();
              if (code.isEmpty) return;
              
              Navigator.of(ctx).pop();
              final provider = context.read<EventProvider>();
              final eventId = await provider.resolveInviteCode(code);
              
              if (eventId != null && context.mounted) {
                context.push('/events/$eventId');
              } else if (context.mounted) {
                AnimatedToast.show(context, message: provider.error ?? 'Invalid Code', isError: true);
              }
            },
            child: const Text('JOIN'),
          ),
        ],
      ),
    );
  }
}
