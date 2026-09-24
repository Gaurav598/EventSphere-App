import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:frontend/features/events/providers/event_provider.dart';
import 'package:frontend/features/events/models/event.dart';
import 'package:frontend/features/tickets/providers/ticket_provider.dart';
import 'package:frontend/shared/widgets/loading_view.dart';
import 'package:frontend/shared/widgets/empty_state_view.dart';
import 'package:frontend/shared/widgets/animated_toast.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:frontend/core/constants.dart';

class EventDetailsScreen extends StatefulWidget {
  final String eventId;
  const EventDetailsScreen({super.key, required this.eventId});

  @override
  State<EventDetailsScreen> createState() => _EventDetailsScreenState();
}

class _EventDetailsScreenState extends State<EventDetailsScreen> with SingleTickerProviderStateMixin {
  Event? _event;
  bool _isLoading = true;
  String? _error;
  late AnimationController _animController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    _fadeAnimation = CurvedAnimation(parent: _animController, curve: Curves.easeIn);
    _loadEvent();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  Future<void> _loadEvent() async {
    try {
      final provider = context.read<EventProvider>();
      final event = await provider.getEventDetails(widget.eventId);
      if (mounted) {
        setState(() {
          _event = event;
          _isLoading = false;
          _error = null;
        });
        _animController.forward();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _register() async {
    final ticketProvider = context.read<TicketProvider>();
    final success = await ticketProvider.register(widget.eventId);
    if (!mounted) return;
    
    if (success) {
      final status = ticketProvider.lastRegistration?['status'];
      final message = status == 'pending'
          ? 'Registration submitted for organizer approval.'
          : status == 'waitlisted'
              ? 'Event is full. You joined the waitlist.'
              : 'Registration confirmed. Your ticket is being prepared.';
      AnimatedToast.show(context, message: message, isError: false);
      _loadEvent(); // Refresh event to get updated capacity
    } else {
      AnimatedToast.show(context, message: ticketProvider.error ?? 'Registration failed', isError: true);
    }
  }

  Widget _buildCapacityVisualization(ThemeData theme) {
    if (_event == null) return const SizedBox.shrink();
    
    final int capacity = _event!.capacity;
    final int registered = _event!.registeredCount;
    final int seatsLeft = capacity > registered ? capacity - registered : 0;
    final double occupancy = capacity > 0 ? (registered / capacity).clamp(0.0, 1.0) : 0.0;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Registered: $registered', style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold)),
            Text('Seats Left: $seatsLeft', style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold, color: seatsLeft == 0 ? Colors.red : Colors.green)),
          ],
        ),
        const SizedBox(height: 8),
        TweenAnimationBuilder<double>(
          duration: const Duration(milliseconds: 800),
          curve: Curves.easeOutCubic,
          tween: Tween<double>(begin: 0, end: occupancy),
          builder: (context, value, child) {
            return ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: value,
                minHeight: 12,
                backgroundColor: theme.colorScheme.surfaceVariant,
                valueColor: AlwaysStoppedAnimation<Color>(
                  value > 0.9 ? Colors.red : (value > 0.7 ? Colors.orange : theme.colorScheme.primary),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Occupancy: ${(occupancy * 100).toStringAsFixed(1)}%', style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey)),
            Text('Total Capacity: $capacity', style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey)),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text(''), backgroundColor: Colors.transparent, elevation: 0),
        body: const LoadingView(),
      );
    }

    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Event Details'), backgroundColor: Colors.transparent, elevation: 0),
        body: EmptyStateView(message: _error!, icon: Icons.error_outline),
      );
    }

    if (_event == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Event Details'), backgroundColor: Colors.transparent, elevation: 0),
        body: const EmptyStateView(message: 'Event not found', icon: Icons.error_outline),
      );
    }

    final ticketProvider = context.watch<TicketProvider>();
    final theme = Theme.of(context);
    final eventDateFormatted = DateFormat('EEEE, MMMM d, y • h:mm a').format(_event!.eventDate.toLocal());

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text(''),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(
          color: theme.brightness == Brightness.dark ? Colors.white : Colors.black,
          shadows: [Shadow(color: Colors.black.withOpacity(0.3), blurRadius: 4)],
        ),
        actions: [
          IconButton(
            tooltip: context.watch<EventProvider>().isFavorite(widget.eventId) ? 'Remove favorite' : 'Save event',
            icon: Icon(context.watch<EventProvider>().isFavorite(widget.eventId) ? Icons.bookmark : Icons.bookmark_border),
            onPressed: () async {
              final provider = context.read<EventProvider>();
              final saved = await provider.toggleFavorite(widget.eventId);
              if (!context.mounted) return;
              AnimatedToast.show(context, message: saved ? 'Favorites updated' : 'Could not update favorites', isError: !saved);
            },
          ),
          IconButton(
            tooltip: 'Add to calendar',
            icon: const Icon(Icons.calendar_month),
            onPressed: () async {
              final uri = Uri.parse('${Constants.baseUrl}/events/${widget.eventId}/calendar');
              if (!await launchUrl(uri, mode: LaunchMode.externalApplication) && context.mounted) {
                AnimatedToast.show(context, message: 'Could not open calendar export', isError: true);
              }
            },
          ),
        ],
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 20,
              offset: const Offset(0, -5),
            ),
          ],
        ),
        child: SafeArea(
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 18),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              elevation: 4,
              shadowColor: theme.colorScheme.primary.withOpacity(0.4),
            ),
            onPressed: (_event!.isRegistrationOpen && (_event!.registeredCount < _event!.capacity || _event!.allowWaitlist) && !ticketProvider.isLoading)
                ? _register
                : null,
            child: ticketProvider.isLoading
                ? const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : Text(
                    _event!.isRegistrationOpen 
                        ? (_event!.registeredCount < _event!.capacity ? 'REGISTER NOW' : (_event!.allowWaitlist ? 'JOIN WAITLIST' : 'EVENT FULL'))
                        : 'REGISTRATION CLOSED',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1),
                  ),
          ),
        ),
      ),
      body: FadeTransition(
        opacity: _fadeAnimation,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Hero Banner with Gradient
              Container(
                height: 300,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      theme.colorScheme.primary,
                      theme.colorScheme.secondary,
                    ],
                  ),
                  image: const DecorationImage(
                    image: AssetImage('assets/images/auth_bg.png'),
                    fit: BoxFit.cover,
                    colorFilter: ColorFilter.mode(Colors.black38, BlendMode.darken),
                  ),
                ),
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            _event!.category.toUpperCase(),
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 1),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _event!.name,
                          style: theme.textTheme.displaySmall?.copyWith(color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              
              Transform.translate(
                offset: const Offset(0, -20),
                child: Container(
                  decoration: BoxDecoration(
                    color: theme.scaffoldBackgroundColor,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Details Row
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(color: theme.colorScheme.primary.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
                              child: Icon(Icons.calendar_today, color: theme.colorScheme.primary),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(eventDateFormatted, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(color: theme.colorScheme.secondary.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
                              child: Icon(Icons.location_on, color: theme.colorScheme.secondary),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(_event!.location, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                                ],
                              ),
                            ),
                          ],
                        ),
                        
                        const Padding(padding: EdgeInsets.symmetric(vertical: 24), child: Divider()),
                        
                        // Capacity Visualization
                        Text('Availability', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 16),
                        _buildCapacityVisualization(theme),
                        
                        const Padding(padding: EdgeInsets.symmetric(vertical: 24), child: Divider()),
                        
                        // About Section
                        Text('About this Event', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 16),
                        Text(
                          _event!.description,
                          style: theme.textTheme.bodyLarge?.copyWith(height: 1.6, color: theme.textTheme.bodyLarge?.color?.withOpacity(0.8)),
                        ),
                        
                        const Padding(padding: EdgeInsets.symmetric(vertical: 24), child: Divider()),
                        
                        // Terms & Conditions (Dummy Data)
                        Text('Terms & Conditions', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surface,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: theme.colorScheme.onSurface.withOpacity(0.1)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildBulletPoint(theme, 'Tickets are non-refundable and non-transferable.'),
                              _buildBulletPoint(theme, 'Please bring a valid photo ID matching the ticket name.'),
                              _buildBulletPoint(theme, 'The organizers reserve the right to alter the schedule without prior notice.'),
                              _buildBulletPoint(theme, 'By registering, you agree to adhere to the code of conduct of the event.'),
                            ],
                          ),
                        ),
                        const SizedBox(height: 32),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBulletPoint(ThemeData theme, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('•', style: TextStyle(fontSize: 18, color: theme.colorScheme.primary, fontWeight: FontWeight.bold)),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: theme.textTheme.bodyMedium?.copyWith(height: 1.4, color: theme.textTheme.bodyMedium?.color?.withOpacity(0.7)))),
        ],
      ),
    );
  }
}
