import 'package:dio/dio.dart';
import 'package:frontend/core/models/paginated_response.dart';
import 'package:frontend/features/events/models/event.dart';

class AdminService {
  final Dio dio;

  AdminService(this.dio);

  Future<PaginatedResponse<Event>> getMyEvents({int page = 1, int limit = 20}) async {
    final response = await dio.get('/admin/events', queryParameters: {'page': page, 'limit': limit});
    return PaginatedResponse<Event>.fromJson(response.data, Event.fromJson);
  }

  Future<Event> createEvent(Map<String, dynamic> eventData) async {
    final response = await dio.post('/admin/events', data: eventData);
    return Event.fromJson(response.data['data']);
  }

  Future<Event> updateEvent(String eventId, Map<String, dynamic> eventData) async {
    final response = await dio.put('/admin/events/$eventId', data: eventData);
    return Event.fromJson(response.data['data']);
  }

  Future<void> deleteEvent(String eventId) async {
    await dio.delete('/admin/events/$eventId');
  }

  Future<void> closeRegistration(String eventId) async {
    await dio.patch('/admin/events/$eventId/close-registration');
  }

  Future<List<Map<String, dynamic>>> getEventRegistrations(String eventId) async {
    final response = await dio.get('/admin/events/$eventId/registrations');
    return List<Map<String, dynamic>>.from(response.data['data']);
  }

  Future<void> updateRegistrationStatus(String regId, String status) async {
    await dio.put('/admin/registrations/$regId/status', data: {'status': status});
  }

  Future<String> exportRegistrations(String eventId) async {
    final response = await dio.get(
      '/admin/events/$eventId/registrations/export',
      options: Options(responseType: ResponseType.plain),
    );
    return response.data as String;
  }

  Future<List<dynamic>> getTopEvents() async {
    final response = await dio.get('/admin/analytics/top-events');
    return response.data['data'] as List;
  }

  Future<List<dynamic>> getCategoryWise() async {
    final response = await dio.get('/admin/analytics/category-wise');
    return response.data['data'] as List;
  }

  Future<List<dynamic>> getMonthlyTrend() async {
    final response = await dio.get('/admin/analytics/monthly-trend');
    return response.data['data'] as List;
  }

  Future<Map<String, dynamic>> getAnalyticsSummary() async {
    final response = await dio.get('/admin/analytics/summary');
    return response.data['data'] as Map<String, dynamic>;
  }

  Future<void> checkinAttendee(String eventId, String ticketPayload) async {
    await dio.post('/admin/events/$eventId/checkin', data: {'ticketPayload': ticketPayload});
  }
}
