import 'package:flutter/material.dart';
import '../domain/models.dart';
import '../data/app_state.dart';
import 'contract_create_flow.dart';

class ContractEditPage extends StatelessWidget {
  final AppState state;
  final Contract? editing;
  const ContractEditPage({super.key, required this.state, this.editing});

  @override
  Widget build(BuildContext context) {
    return ContractCreateFlow(state: state, editing: editing);
  }
}
