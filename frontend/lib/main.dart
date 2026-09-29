import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';

// Core
import 'package:frontend/core/api_client.dart';
import 'package:frontend/core/theme.dart';

// Services
import 'package:frontend/features/auth/services/auth_service.dart';
import 'package:frontend/features/events/services/event_service.dart';
import 'package:frontend/features/tickets/services/ticket_service.dart';
import 'package:frontend/features/admin/services/admin_service.dart';
import 'package:frontend/core/theme_provider.dart';

// Providers
import 'package:frontend/features/auth/providers/auth_provider.dart';
import 'package:frontend/features/events/providers/event_provider.dart';
import 'package:frontend/features/tickets/providers/ticket_provider.dart';
import 'package:frontend/features/admin/providers/admin_provider.dart';

// UI - Auth
import 'package:frontend/features/auth/ui/splash_screen.dart';
import 'package:frontend/features/auth/ui/login_screen.dart';
import 'package:frontend/features/auth/ui/signup_screen.dart';
import 'package:frontend/features/auth/ui/profile_screen.dart';

// UI - User
import 'package:frontend/features/events/ui/event_list_screen.dart';
import 'package:frontend/features/events/ui/event_details_screen.dart';
import 'package:frontend/features/tickets/ui/my_tickets_screen.dart';
import 'package:frontend/features/tickets/ui/ticket_details_screen.dart';
import 'package:frontend/features/tickets/models/ticket.dart';

// UI - Admin
import 'package:frontend/features/admin/ui/admin_dashboard.dart';
import 'package:frontend/features/admin/ui/create_event_screen.dart';
import 'package:frontend/features/admin/ui/edit_event_screen.dart';
import 'package:frontend/features/admin/ui/event_registrations_screen.dart';
import 'package:frontend/features/admin/ui/qr_scanner_screen.dart';

import 'package:frontend/features/events/models/event.dart';

void main() {
  final apiClient = ApiClient();
  final authProvider = AuthProvider(AuthService(apiClient.dio));
  apiClient.onUnauthorized = authProvider.handleUnauthorized;

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: authProvider),
        ChangeNotifierProvider(
          create: (_) => EventProvider(EventService(apiClient.dio)),
        ),
        ChangeNotifierProvider(
          create: (_) => TicketProvider(TicketService(apiClient.dio)),
        ),
        ChangeNotifierProvider(
          create: (_) => AdminProvider(AdminService(apiClient.dio)),
        ),
        ChangeNotifierProvider(
          create: (_) => ThemeProvider(),
        ),
      ],
      child: const EventSphereApp(),
    ),
  );
}

class EventSphereApp extends StatefulWidget {
  const EventSphereApp({super.key});

  @override
  State<EventSphereApp> createState() => _EventSphereAppState();
}

class _EventSphereAppState extends State<EventSphereApp> {
  late final GoRouter _router;

  late final AuthProvider _authProvider;

  @override
  void initState() {
    super.initState();
    _authProvider = context.read<AuthProvider>();
    
    _router = GoRouter(
      initialLocation: '/',
      refreshListenable: _authProvider,
      redirect: (context, state) {
        final isInitializing = _authProvider.isInitializing;
        final isAuthenticated = _authProvider.isAuthenticated;
        final isAdmin = _authProvider.isAdmin;
        final isAuthRoute = state.matchedLocation == '/login' || state.matchedLocation == '/signup';
        final isSplashRoute = state.matchedLocation == '/';

        if (isInitializing) {
          return isSplashRoute ? null : '/';
        }

        if (!isAuthenticated) {
          if (!isAuthRoute) return '/login';
          return null;
        }

        if (isAuthenticated && (isAuthRoute || isSplashRoute)) {
          return isAdmin ? '/admin' : '/events';
        }

        final isAdminRoute = state.matchedLocation.startsWith('/admin');
        final isProfileRoute = state.matchedLocation == '/profile';
        if (isAdminRoute && !isAdmin) {
          return '/events';
        }
        if (!isAdminRoute && !isProfileRoute && isAdmin && state.matchedLocation != '/') {
          return '/admin';
        }

        return null;
      },
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => const SplashScreen(),
        ),
        GoRoute(
          path: '/login',
          builder: (context, state) => const LoginScreen(),
        ),
        GoRoute(
          path: '/signup',
          builder: (context, state) => const SignupScreen(),
        ),
        GoRoute(
          path: '/events',
          builder: (context, state) => const EventListScreen(),
        ),
        GoRoute(
          path: '/profile',
          builder: (context, state) => const ProfileScreen(),
        ),
        GoRoute(
          path: '/events/:id',
          builder: (context, state) {
            final id = state.pathParameters['id']!;
            return EventDetailsScreen(eventId: id);
          },
        ),
        GoRoute(
          path: '/tickets',
          builder: (context, state) => const MyTicketsScreen(),
        ),
        GoRoute(
          path: '/tickets/:id',
          builder: (context, state) {
            final ticket = state.extra;
            return ticket is Ticket
                ? TicketDetailsScreen(ticket: ticket)
                : const MyTicketsScreen();
          },
        ),
        GoRoute(
          path: '/admin',
          builder: (context, state) => const AdminDashboard(),
        ),
        GoRoute(
          path: '/admin/create-event',
          builder: (context, state) => const CreateEventScreen(),
        ),
        GoRoute(
          path: '/admin/events/:id/edit',
          builder: (context, state) {
            final event = state.extra as Event;
            return EditEventScreen(event: event);
          },
        ),
        GoRoute(
          path: '/admin/events/:id/registrations',
          builder: (context, state) {
            final event = state.extra as Event;
            return EventRegistrationsScreen(event: event);
          },
        ),
        GoRoute(
          path: '/admin/events/:id/scan',
          builder: (context, state) {
            final eventId = state.pathParameters['id']!;
            return QRScannerScreen(eventId: eventId);
          },
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeProvider>(
      builder: (context, themeProvider, _) {
        return MaterialApp.router(
          title: 'EventSphere',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: themeProvider.themeMode,
          routerConfig: _router,
        );
      },
    );
  }
}
