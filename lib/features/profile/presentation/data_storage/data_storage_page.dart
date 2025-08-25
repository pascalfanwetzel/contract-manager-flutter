import 'package:flutter/material.dart';
import '../../../contracts/data/app_state.dart';
import 'trash_view.dart';

class DataStoragePage extends StatelessWidget {
  final AppState state;
  const DataStoragePage({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 1,
      child: Column(
        children: [
          const TabBar(
            tabs: [
              Tab(text: 'Trash / Recently Deleted'),
            ],
          ),
          Expanded(
            child: TabBarView(
              physics: const NeverScrollableScrollPhysics(),
              children: [
                TrashView(state: state),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
