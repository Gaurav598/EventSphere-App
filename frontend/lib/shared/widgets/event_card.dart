import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:frontend/features/events/models/event.dart';

class EventCard extends StatelessWidget {
  final Event event;
  final VoidCallback onTap;
  final bool isFavorite;
  final VoidCallback? onFavoriteToggle;

  const EventCard({
    super.key,
    required this.event,
    required this.onTap,
    this.isFavorite = false,
    this.onFavoriteToggle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    final int remainingSeats = event.capacity - event.registeredCount;
    final bool isFull = remainingSeats <= 0;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Banner Image
            Hero(
              tag: 'event_image_${event.id}',
              child: Container(
                height: 140,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withOpacity(0.1),
                  image: const DecorationImage(
                    image: AssetImage('assets/images/auth_bg.png'), // Fallback banner
                    fit: BoxFit.cover,
                  ),
                ),
                child: Stack(
                  children: [
                    Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.transparent, Colors.black54],
                        ),
                      ),
                    ),
                    Positioned(
                      top: 8,
                      left: 8,
                      child: IconButton.filledTonal(
                        tooltip: isFavorite ? 'Remove favorite' : 'Save event',
                        onPressed: onFavoriteToggle,
                        icon: Icon(isFavorite ? Icons.bookmark : Icons.bookmark_border),
                      ),
                    ),
                    Positioned(
                      top: 12,
                      right: 12,
                      child: Row(
                        children: [
                          if (event.isPrivate)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.black87,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Row(
                                children: [
                                  Icon(Icons.lock, size: 14, color: Colors.white),
                                  SizedBox(width: 4),
                                  Text('PRIVATE', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                                ],
                              ),
                            ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.secondary,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              event.category.toUpperCase(),
                              style: const TextStyle(color: Colors.black, fontSize: 10, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            
            // Content
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    event.name,
                    style: theme.textTheme.titleLarge,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(Icons.calendar_today, size: 16, color: theme.colorScheme.onSurface.withOpacity(0.6)),
                      const SizedBox(width: 8),
                      Text(
                        DateFormat('MMM d, yyyy • h:mm a').format(event.eventDate.toLocal()),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurface.withOpacity(0.8),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.location_on, size: 16, color: theme.colorScheme.onSurface.withOpacity(0.6)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          event.location,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurface.withOpacity(0.8),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '${event.registeredCount} / ${event.capacity} Seats Filled',
                        style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        '${(event.capacity > 0 ? (event.registeredCount / event.capacity * 100) : 0).toStringAsFixed(0)}%',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: isFull ? theme.colorScheme.error : theme.colorScheme.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  TweenAnimationBuilder<double>(
                    duration: const Duration(milliseconds: 500),
                    curve: Curves.easeOut,
                    tween: Tween<double>(
                      begin: 0,
                      end: event.capacity > 0 ? (event.registeredCount / event.capacity).clamp(0.0, 1.0) : 0,
                    ),
                    builder: (context, value, child) {
                      return ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: value,
                          minHeight: 6,
                          backgroundColor: theme.colorScheme.surfaceVariant,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            isFull ? theme.colorScheme.error : theme.colorScheme.primary,
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: event.isRegistrationOpen && (!isFull || event.allowWaitlist) ? onTap : null,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      ),
                      child: Text(
                        !event.isRegistrationOpen
                            ? 'REGISTRATION CLOSED'
                            : isFull && event.allowWaitlist
                                ? 'VIEW WAITLIST'
                                : isFull
                                    ? 'SOLD OUT'
                                    : 'VIEW EVENT',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
