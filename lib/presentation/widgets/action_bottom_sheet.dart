import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

class SheetAction {
  const SheetAction({
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.isDestructive = false,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  final bool isDestructive;
}

class ActionBottomSheet extends StatelessWidget {
  const ActionBottomSheet({
    super.key,
    required this.title,
    required this.actions,
  });

  final String title;
  final List<SheetAction> actions;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 12),
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            ...actions.map((action) {
              final color = action.isDestructive ? AppTheme.danger : Colors.white;
              return ListTile(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
                leading: Icon(action.icon, color: color),
                title: Text(
                  action.title,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                subtitle: action.subtitle == null
                    ? null
                    : Text(
                        action.subtitle!,
                        style: const TextStyle(color: AppTheme.mutedText),
                      ),
                onTap: action.onTap,
              );
            }),
          ],
        ),
      ),
    );
  }
}
