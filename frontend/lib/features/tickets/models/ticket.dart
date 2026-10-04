import 'package:frontend/features/events/models/event.dart';

/// An attendee registration and its optional issued ticket.
class Ticket {
  final String id;
  final String eventId;
  final String userId;
  final String status;
  final String ticketStatus;
  final DateTime registeredAt;
  final int? waitlistPosition;
  final String? qrPayload;
  final String? qrImageRef;
  final Event? event;

  const Ticket({
    required this.id,
    required this.eventId,
    required this.userId,
    required this.status,
    required this.ticketStatus,
    required this.registeredAt,
    this.waitlistPosition,
    this.qrPayload,
    this.qrImageRef,
    this.event,
  });

  bool get canDisplayTicket =>
      (status == 'confirmed' || status == 'checked_in') && qrPayload != null;
  bool get canCancel =>
      const {'pending', 'waitlisted', 'confirmed'}.contains(status);

  factory Ticket.fromJson(Map<String, dynamic> json) => Ticket(
        id: json['_id'] ?? json['registrationId'] ?? json['id'] ?? '',
        eventId: json['eventId'] ?? '',
        userId: json['userId'] ?? '',
        status: json['status'] ?? 'pending',
        ticketStatus: json['ticketStatus'] ?? 'NOT_REQUIRED',
        registeredAt: DateTime.tryParse(json['registeredAt'] ?? '') ?? DateTime.now(),
        waitlistPosition: json['waitlistPosition'] as int?,
        qrPayload: json['qrPayload'],
        qrImageRef: json['qrImageRef'],
        event: json['event'] is Map<String, dynamic>
            ? Event.fromJson(json['event'])
            : null,
      );

  Ticket withIssuedTicket(Map<String, dynamic> json) => Ticket(
        id: id,
        eventId: eventId,
        userId: userId,
        status: status,
        ticketStatus: json['ticketStatus'] ?? 'READY',
        registeredAt: registeredAt,
        waitlistPosition: waitlistPosition,
        qrPayload: json['qrPayload'],
        qrImageRef: json['qrImageRef'],
        event: event,
      );

  Map<String, dynamic> toJson() => {
        '_id': id,
        'eventId': eventId,
        'userId': userId,
        'status': status,
        'ticketStatus': ticketStatus,
        'registeredAt': registeredAt.toIso8601String(),
        'waitlistPosition': waitlistPosition,
        'qrPayload': qrPayload,
        'qrImageRef': qrImageRef,
        if (event != null) 'event': event!.toJson(),
      };
}
