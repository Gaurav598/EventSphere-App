import 'package:dio/dio.dart';
import 'package:frontend/core/models/paginated_response.dart';
import 'package:frontend/features/events/models/event.dart';

class EventService {
  final Dio dio;

  EventService(this.dio);

  Future<PaginatedResponse<Event>> getEvents({
    int page = 1,
    int limit = 10,
    String? category,
    DateTime? dateFrom,
    DateTime? dateTo,
  }) async {
    final Map<String, dynamic> queryParams = {
      'page': page,
      'limit': limit,
    };
    if (category != null && category.isNotEmpty) {
      queryParams['category'] = category;
    }
    if (dateFrom != null) queryParams['date_from'] = dateFrom.toUtc().toIso8601String();
    if (dateTo != null) queryParams['date_to'] = dateTo.toUtc().toIso8601String();
    
    final response = await dio.get('/events', queryParameters: queryParams);
    return PaginatedResponse<Event>.fromJson(response.data, Event.fromJson);
  }

  Future<PaginatedResponse<Event>> searchEvents(String query, {int page = 1, int limit = 10}) async {
    final response = await dio.get('/events/search', queryParameters: {'q': query, 'page': page, 'limit': limit});
    return PaginatedResponse<Event>.fromJson(response.data, Event.fromJson);
  }

  Future<Event> getEventDetails(String id) async {
    final response = await dio.get('/events/$id');
    return Event.fromJson(response.data['data']);
  }

  Future<Event> getEventByInviteCode(String inviteCode) async {
    final response = await dio.get('/events/invite/$inviteCode');
    return Event.fromJson(response.data['data']);
  }

  Future<List<Event>> getFavorites() async {
    final response = await dio.get('/favorites');
    return (response.data['data'] as List)
        .map((item) => Event.fromJson(Map<String, dynamic>.from(item)))
        .toList();
  }

  Future<void> setFavorite(String eventId, bool favorite) async {
    if (favorite) {
      await dio.post('/events/$eventId/favorite');
    } else {
      await dio.delete('/events/$eventId/favorite');
    }
  }
}
