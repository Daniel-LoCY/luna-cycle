import 'package:material_ui/material_ui.dart';

import 'theme.dart';

class LunaPage extends StatelessWidget {
  const LunaPage({
    super.key,
    required this.title,
    required this.children,
    this.action,
  });
  final String title;
  final Widget? action;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => CustomScrollView(
    slivers: [
      SliverAppBar(
        pinned: true,
        title: Text(
          title,
          style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w700),
        ),
        actions: action == null ? null : [action!],
      ),
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 32),
        sliver: SliverList.list(children: children),
      ),
    ],
  );
}

class LunaCard extends StatelessWidget {
  const LunaCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
  });
  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(padding: padding, child: child),
  );
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
  });
  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) => LunaCard(
    child: Column(
      children: [
        Icon(icon, size: 30, color: LunaColors.lavender),
        const SizedBox(height: 10),
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 6),
        Text(
          message,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ],
    ),
  );
}
