class Event {
  final String id;
  final String name;
  final String description;
  final String category;
  final String location;
  final DateTime eventDate;
  final DateTime? eventEndDate;
  final DateTime registrationDeadline;
  final int capacity;
  final int registeredCount;
  final bool isRegistrationOpen;
  final bool isPrivate;
  final String? inviteCode;
  final bool allowWaitlist;

  Event({
    required this.id,
    required this.name,
    required this.description,
    required this.category,
    required this.location,
    required this.eventDate,
    this.eventEndDate,
    required this.registrationDeadline,
    required this.capacity,
    required this.registeredCount,
    required this.isRegistrationOpen,
    this.isPrivate = false,
    this.inviteCode,
    this.allowWaitlist = true,
  });

  factory Event.fromJson(Map<String, dynamic> json) {
    return Event(
      id: json['_id'] ?? json['id'] ?? '',
      name: json['name'] ?? '',
      description: json['description'] ?? '',
      category: json['category'] ?? '',
      location: json['location'] ?? '',
      eventDate: DateTime.parse(json['eventDate'] ?? DateTime.now().toIso8601String()),
      eventEndDate: json['eventEndDate'] == null ? null : DateTime.tryParse(json['eventEndDate']),
      registrationDeadline: DateTime.parse(json['registrationDeadline'] ?? DateTime.now().toIso8601String()),
      capacity: json['capacity'] ?? 0,
      registeredCount: json['registeredCount'] ?? 0,
      isRegistrationOpen: json['isRegistrationOpen'] ?? false,
      isPrivate: json['isPrivate'] ?? false,
      inviteCode: json['inviteCode'],
      allowWaitlist: json['allowWaitlist'] ?? true,
    );
  }

  Map<String, dynamic> toJson() => {
        '_id': id,
        'name': name,
        'description': description,
        'category': category,
        'location': location,
        'eventDate': eventDate.toIso8601String(),
        'eventEndDate': eventEndDate?.toIso8601String(),
        'registrationDeadline': registrationDeadline.toIso8601String(),
        'capacity': capacity,
        'registeredCount': registeredCount,
        'isRegistrationOpen': isRegistrationOpen,
        'isPrivate': isPrivate,
        'inviteCode': inviteCode,
        'allowWaitlist': allowWaitlist,
      };
}
