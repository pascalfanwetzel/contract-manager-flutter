import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../features/contracts/data/app_state.dart';
import '../features/overview/presentation/overview_page.dart';
import '../features/contracts/presentation/contracts_page.dart';
import '../features/contracts/presentation/contract_view.dart';
import '../features/contracts/presentation/contract_edit_page.dart';
import '../features/profile/presentation/profile_page.dart';
import '../features/profile/presentation/views/user_info_view.dart';
import '../features/profile/presentation/views/settings_view.dart';
import '../features/profile/presentation/views/notifications_view.dart';
import '../features/profile/presentation/data_storage/data_storage_page.dart';
import '../features/profile/presentation/views/privacy_view.dart';
import '../features/profile/presentation/views/help_feedback_view.dart';
import '../features/contracts/domain/models.dart';
import '../features/auth/welcome_page.dart';
import '../core/auth/auth_service.dart';
import '../features/auth/unlock_page.dart';
import 'routes.dart';
import 'shell.dart';

final appState = AppState(); // single in-memory source of truth

class GoRouterRefreshStream extends ChangeNotifier {
  GoRouterRefreshStream(Stream<dynamic> stream) {
    _sub = stream.asBroadcastStream().listen((_) => notifyListeners());
  }
  late final StreamSubscription _sub;
  @override
  void dispose() { _sub.cancel(); super.dispose(); }
}

final router = GoRouter(
  refreshListenable: GoRouterRefreshStream(AuthService.instance.userChanges),
  redirect: (context, state) {
    final signedIn = AuthService.instance.currentUser != null;
    final atWelcome = state.uri.toString() == AppRoutes.welcome;
    if (!signedIn && !atWelcome) return AppRoutes.welcome;
    // After sign-in, route to unlock screen first for a smoother E2EE setup
    if (signedIn && atWelcome) return AppRoutes.unlock;
    return null;
  },
  routes: [
    GoRoute(
      path: AppRoutes.welcome,
      builder: (context, state) => const WelcomePage(),
    ),
    GoRoute(
      path: AppRoutes.unlock,
      builder: (context, state) => UnlockPage(state: appState),
    ),
    ShellRoute(
      builder: (context, state, child) => HomeShell(state: appState, child: child),
      routes: [
        GoRoute(
          path: AppRoutes.overview,
          pageBuilder: (context, state) => CustomTransitionPage(
            child: OverviewPage(state: appState),
            transitionDuration: const Duration(milliseconds: 160),
            transitionsBuilder: (context, animation, secondaryAnimation, child) =>
                FadeTransition(opacity: animation, child: child),
          ),
        ),
        GoRoute(
          path: AppRoutes.contracts,
          pageBuilder: (context, state) => CustomTransitionPage(
            child: ContractsPage(
              state: appState,
              initialCategoryId: state.extra is String ? state.extra as String : null,
            ),
            transitionDuration: const Duration(milliseconds: 160),
            transitionsBuilder: (context, animation, secondaryAnimation, child) =>
                FadeTransition(opacity: animation, child: child),
          ),
          routes: [
            // /contracts/new  (also used for EDIT via state.extra)
            GoRoute(
              path: 'new',
              builder: (context, state) {
                final editing = state.extra as Contract?;
                return ContractEditPage(state: appState, editing: editing);
              },
            ),
            // /contracts/:id  (optional details route)
            GoRoute(
              path: ':id',
              builder: (context, state) {
                final id = state.pathParameters['id']!;
                final c = appState.contractById(id);
                if (c == null) {
                  return const Scaffold(
                    body: Center(child: Text('Contract not found')),
                  );
                }
                return ContractView(state: appState, contract: c);
              },
            ),
          ],
        ),
        GoRoute(
          path: AppRoutes.profile,
          pageBuilder: (context, state) => CustomTransitionPage(
            child: ProfilePage(state: appState),
            transitionDuration: const Duration(milliseconds: 160),
            transitionsBuilder: (context, animation, secondaryAnimation, child) =>
                FadeTransition(opacity: animation, child: child),
          ),
          routes: [
            GoRoute(
              path: 'user',
              builder: (context, state) => Scaffold(
                appBar: AppBar(title: const Text('User Information')),
                body: UserInfoView(state: appState),
              ),
            ),
            GoRoute(
              path: 'settings',
              builder: (context, state) => Scaffold(
                appBar: AppBar(title: const Text('Settings')),
                body: SettingsView(state: appState),
              ),
            ),
            GoRoute(
              path: 'notifications',
              builder: (context, state) => Scaffold(
                appBar: AppBar(title: const Text('Notifications & Reminders')),
                body: NotificationsView(state: appState),
              ),
            ),
            GoRoute(
              path: 'storage',
              builder: (context, state) => Scaffold(
                appBar: AppBar(title: const Text('Data & Storage')),
                body: DataStoragePage(state: appState),
              ),
            ),
            GoRoute(
              path: 'privacy',
              builder: (context, state) => Scaffold(
                appBar: AppBar(title: const Text('Privacy')),
                body: PrivacyView(state: appState),
              ),
            ),
            GoRoute(
              path: 'help',
              builder: (context, state) => Scaffold(
                appBar: AppBar(title: const Text('Help & Feedback')),
                body: HelpFeedbackView(state: appState),
              ),
            ),
          ],
        ),
      ],
    ),
  ],
);
