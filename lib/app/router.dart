// lib/app/router.dart
import 'package:go_router/go_router.dart';
import '../features/contracts/data/app_state.dart';
import '../features/contracts/presentation/contracts_page.dart';
import '../features/contracts/presentation/contract_edit_page.dart';

// One shared state instance for all routes
final appState = AppState();

final router = GoRouter(
  routes: [
    GoRoute(
      path: '/',
      builder: (_, __) => ContractsPage(state: appState),
    ),
    GoRoute(
      path: '/contracts/new',
      builder: (_, __) => ContractEditPage(state: appState),
    ),
    // detail route can come later
  ],
);
