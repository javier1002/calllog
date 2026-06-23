import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

class TopSearchHeader extends StatelessWidget {
  const TopSearchHeader({
    super.key,
    required this.title,
    required this.searchController,
    required this.hintText,
    required this.menuItems,
    required this.onMenuSelected,
  });

  final String title;
  final TextEditingController searchController;
  final String hintText;
  final List<PopupMenuEntry<String>> menuItems;
  final ValueChanged<String> onMenuSelected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 40,
                    height: 1,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -1.2,
                  ),
                ),
              ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert_rounded, size: 30),
                color: AppTheme.surfaceHigh,
                onSelected: onMenuSelected,
                itemBuilder: (_) => menuItems,
              ),
            ],
          ),
          const SizedBox(height: 20),
          SearchBar(
            controller: searchController,
            hintText: hintText,
            leading: const Icon(Icons.search_rounded, size: 28),
            elevation: const WidgetStatePropertyAll(0),
            backgroundColor: const WidgetStatePropertyAll(Color(0xFF111820)),
            shadowColor: const WidgetStatePropertyAll(Colors.transparent),
            shape: WidgetStatePropertyAll(
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
            ),
            textStyle: const WidgetStatePropertyAll(
              TextStyle(fontSize: 20, color: Colors.white),
            ),
            hintStyle: const WidgetStatePropertyAll(
              TextStyle(fontSize: 20, color: AppTheme.mutedText),
            ),
            trailing: [
              if (searchController.text.isNotEmpty)
                IconButton(
                  tooltip: 'Limpiar búsqueda',
                  onPressed: searchController.clear,
                  icon: const Icon(Icons.close_rounded),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
