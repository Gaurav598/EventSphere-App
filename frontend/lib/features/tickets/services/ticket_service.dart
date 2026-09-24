import 'package:dio/dio.dart';
import 'package:frontend/features/tickets/models/ticket.dart';

class TicketService {
  final Dio dio;

  TicketService(this.dio);

  Future<Map<String, dynamic>> registerForEvent(String eventId) async {
    final response = await dio.post('/events/$eventId/register');
    return Map<String, dynamic>.from(response.data['data']);
  }

  Future<List<Ticket>> getMyTickets() async {
    final response = await dio.get('/registrations/me');
    return (response.data['data'] as List)
        .map((item) => Ticket.fromJson(Map<String, dynamic>.from(item)))
        .toList();
  }

  Future<Map<String, dynamic>> getIssuedTicket(String registrationId) async {
    final response = await dio.get('/registrations/$registrationId/ticket');
    return Map<String, dynamic>.from(response.data['data']);
  }

  Future<void> cancelRegistration(String registrationId) async {
    await dio.delete('/registrations/$registrationId');
  }

  Future<void> retryTicket(String registrationId) async {
    await dio.post('/registrations/$registrationId/ticket/retry');
  }
}
