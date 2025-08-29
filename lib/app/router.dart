import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../features/contracts/data/app_state.dart';
import '../features/overview/presentation/overview_page.dart';
import '../features/contracts/presentation/contracts_page.dart';
import '../features/contracts/presentation/contract_view.dart';
import '../features/contracts/presentation/contract_edit_page.dart';
import '../features/profile/presentation/profile_page.dart';
import '../features/contracts/domain/models.dart';
import 'routes.dart';
import 'shell.dart';

final appState = AppState(); // single in-memory source of truth

final router = GoRouter(
  routes: [
    ShellRoute(
      builder: (context, state, child) => HomeShell(state: appState, child: child),
      routes: [
        GoRoute(
          path: AppRoutes.overview,
          builder: (context, state) => OverviewPage(state: appState),
        ),
        GoRoute(
          path: AppRoutes.contracts,
          builder: (_, state) => ContractsPage(
            state: appState,
            initialCategoryId: state.extra is String ? state.extra as String : null,
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
          builder: (context, state) => ProfilePage(state: appState),
        ),
      ],
    ),
  ],
);
