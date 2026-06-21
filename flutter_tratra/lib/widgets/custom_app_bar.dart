// widgets/custom_app_bar.dart
import 'package:flutter/material.dart';

class CustomAppBar extends StatelessWidget implements PreferredSizeWidget {
  const CustomAppBar({
    super.key,
    required String title,
    required bool showBackButton,
    required Widget? leading,
  });

  @override
  Widget build(BuildContext context) {
    return AppBar(
      title: Row(
        children: [
          const Icon(Icons.location_on, color: Color(0xFF00B14F), size: 20),
          const SizedBox(width: 8),
          Text('Paris 15ème', style: Theme.of(context).textTheme.bodyLarge),
          const Icon(Icons.arrow_drop_down, color: Colors.grey),
        ],
      ),
      actions: [
        IconButton(
          icon: Badge(
            backgroundColor: Colors.red,
            child: const Icon(Icons.notifications_none, color: Colors.black54),
          ),
          onPressed: () {},
        ),
      ],
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}
