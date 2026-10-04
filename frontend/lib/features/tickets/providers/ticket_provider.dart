import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:frontend/core/api_client.dart';
import 'package:frontend/core/secure_storage.dart';
import 'package:frontend/features/tickets/models/ticket.dart';
import 'package:frontend/features/tickets/services/ticket_service.dart';

class TicketProvider extends ChangeNotifier {
  final TicketService _ticketService;

  List<Ticket> _myTickets = [];
  bool _isLoading = false;
  String? _error;
  Map<String, dynamic>? _lastRegistration;

  TicketProvider(this._ticketService);

  List<Ticket> get myTickets => _myTickets;
  bool get isLoading => _isLoading;
  String? get error => _error;
  Map<String, dynamic>? get lastRegistration => _lastRegistration;

  Future<void> fetchMyTickets() async {
    _setLoading(true);
    try {
      _myTickets = await _ticketService.getMyTickets();
    } catch (error) {
      _error = _message(error, 'Failed to load registrations');
    } finally {
      _setLoading(false, clearError: false);
    }
  }

  Future<bool> register(String eventId, {String? inviteCode}) async {
    _setLoading(true);
    try {
      _lastRegistration = await _ticketService.registerForEvent(eventId, inviteCode: inviteCode);
      _myTickets = await _ticketService.getMyTickets();
      return true;
    } catch (error) {
      _error = _message(error, 'Registration failed');
      return false;
    } finally {
      _setLoading(false, clearError: false);
    }
  }

  Future<Ticket?> loadIssuedTicket(Ticket registration) async {
    _setLoading(true);
    try {
      final issued = await _ticketService.getIssuedTicket(registration.id);
      final complete = registration.withIssuedTicket(issued);
      await SecureStorage.cacheTicket(registration.id, complete.toJson());
      _replace(complete);
      return complete;
    } catch (error) {
      final serverRejectedTicket = error is DioException && error.response != null;
      if (!serverRejectedTicket) {
        final cached = await SecureStorage.getCachedTicket(registration.id);
        if (cached != null) {
          final offline = Ticket.fromJson(cached);
          _replace(offline);
          _error = 'Showing a downloaded ticket offline. Check-in still requires server validation.';
          return offline;
        }
      }
      _error = _message(error, 'Ticket is not ready yet');
      return null;
    } finally {
      _setLoading(false, clearError: false);
    }
  }

  Future<bool> cancel(String registrationId) async {
    _setLoading(true);
    try {
      await _ticketService.cancelRegistration(registrationId);
      await SecureStorage.removeCachedTicket(registrationId);
      _myTickets = await _ticketService.getMyTickets();
      return true;
    } catch (error) {
      _error = _message(error, 'Cancellation failed');
      return false;
    } finally {
      _setLoading(false, clearError: false);
    }
  }

  Future<bool> retryTicket(String registrationId) async {
    _setLoading(true);
    try {
      await _ticketService.retryTicket(registrationId);
      await fetchMyTickets();
      return true;
    } catch (error) {
      _error = _message(error, 'Could not retry ticket generation');
      return false;
    } finally {
      _setLoading(false, clearError: false);
    }
  }

  void _replace(Ticket ticket) {
    final index = _myTickets.indexWhere((item) => item.id == ticket.id);
    if (index >= 0) _myTickets[index] = ticket;
  }

  String _message(Object error, String fallback) {
    if (error is DioException && error.error is ApiException) {
      return (error.error as ApiException).message;
    }
    if (error is ApiException) return error.message;
    return fallback;
  }

  void _setLoading(bool value, {bool clearError = true}) {
    _isLoading = value;
    if (clearError) _error = null;
    notifyListeners();
  }
}
