import 'package:flutter/material.dart';
import 'package:frontend/core/models/paginated_response.dart';
import 'package:frontend/features/events/models/event.dart';
import 'package:frontend/features/events/services/event_service.dart';
import 'package:frontend/core/websocket_service.dart';
import 'dart:async';

class EventProvider extends ChangeNotifier {
  final EventService _eventService;

  List<Event> _events = [];
  Pagination? _pagination;
  bool _isLoading = false;
  String? _error;
  StreamSubscription? _wsSubscription;
  String? _lastSearchQuery;
  String? _lastCategory;
  DateTime? _dateFrom;
  DateTime? _dateTo;
  final Set<String> _favoriteIds = {};
  List<Event> _favoriteEvents = [];
  final Map<String, String> _privateInviteCodes = {};

  EventProvider(this._eventService) {
    _wsSubscription = WebSocketService().stream.listen((message) {
      if (message['type'] == 'REGISTRATION_UPDATE' || message['type'] == 'EVENT_UPDATE') {
        if (_lastSearchQuery != null && _lastSearchQuery!.isNotEmpty) {
          searchEvents(_lastSearchQuery!, dateFrom: _dateFrom, dateTo: _dateTo);
        } else {
          fetchEvents(category: _lastCategory, dateFrom: _dateFrom, dateTo: _dateTo);
        }
      }
    });
  }

  @override
  void dispose() {
    _wsSubscription?.cancel();
    super.dispose();
  }

  List<Event> get events => _events;
  Pagination? get pagination => _pagination;
  bool get isLoading => _isLoading;
  String? get error => _error;
  Set<String> get favoriteIds => Set.unmodifiable(_favoriteIds);
  List<Event> get favoriteEvents => List.unmodifiable(_favoriteEvents);
  bool isFavorite(String eventId) => _favoriteIds.contains(eventId);
  String? inviteCodeFor(String eventId) => _privateInviteCodes[eventId];

  Future<void> fetchEvents({String? category, int page = 1, int limit = 20, DateTime? dateFrom, DateTime? dateTo}) async {
    _lastCategory = category;
    _dateFrom = dateFrom;
    _dateTo = dateTo;
    _lastSearchQuery = null;
    _setLoading(true);
    try {
      final response = await _eventService.getEvents(category: category, page: page, limit: limit, dateFrom: dateFrom, dateTo: dateTo);
      _events = response.data;
      _pagination = response.pagination;
      _setLoading(false);
    } catch (e) {
      _error = e.toString();
      _setLoading(false);
    }
  }

  Future<void> searchEvents(String query, {int page = 1, int limit = 20, DateTime? dateFrom, DateTime? dateTo}) async {
    _lastSearchQuery = query;
    _lastCategory = null;
    _dateFrom = dateFrom;
    _dateTo = dateTo;
    if (query.isEmpty) {
      await fetchEvents();
      return;
    }
    _setLoading(true);
    try {
      final response = await _eventService.searchEvents(query, page: page, limit: limit, dateFrom: dateFrom, dateTo: dateTo);
      _events = response.data;
      _pagination = response.pagination;
      _setLoading(false);
    } catch (e) {
      _error = e.toString();
      _setLoading(false);
    }
  }

  Future<String?> resolveInviteCode(String inviteCode) async {
    _setLoading(true);
    try {
      final event = await _eventService.getEventByInviteCode(inviteCode);
      _privateInviteCodes[event.id] = inviteCode;
      _setLoading(false);
      return event.id;
    } catch (e) {
      _error = 'Invalid invite code or event not found';
      _setLoading(false);
      return null;
    }
  }

  Future<void> fetchFavorites() async {
    try {
      final favorites = await _eventService.getFavorites();
      _favoriteEvents = favorites;
      _favoriteIds
        ..clear()
        ..addAll(favorites.map((event) => event.id));
      notifyListeners();
    } catch (_) {
      // Discovery remains usable if favorites cannot be refreshed.
    }
  }

  Future<bool> toggleFavorite(String eventId) async {
    final shouldFavorite = !_favoriteIds.contains(eventId);
    try {
      await _eventService.setFavorite(eventId, shouldFavorite);
      // Refetch the authoritative list so favorites added from private-event
      // details (which may not exist in the discovery page) appear immediately.
      await fetchFavorites();
      return true;
    } catch (error) {
      _error = error.toString();
      notifyListeners();
      return false;
    }
  }

  Future<Event> getEventDetails(String id) async {
    return await _eventService.getEventDetails(id);
  }

  void _setLoading(bool value) {
    _isLoading = value;
    if (value) _error = null;
    notifyListeners();
  }
}
