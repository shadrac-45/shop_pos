/// Lets someone who works in several shops choose one.
library;

import 'package:flutter/material.dart';

import 'package:shop_pos/core/services/cloud_service.dart';
import 'package:shop_pos/features/shared/widgets/glass.dart';

/// The shop to use, or null if cancelled. With one shop it is returned
/// directly.
Future<CloudShop?> pickShop(BuildContext context, List<CloudShop> shops,
    {String title = 'Which shop is this till in?'}) async {
  if (shops.isEmpty) return null;
  if (shops.length == 1) return shops.first;
  return showAppDialog<CloudShop>(
    context: context,
    builder: (ctx) => SimpleDialog(
      title: Text(title),
      children: [
        for (final s in shops)
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, s),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(children: [
                const Icon(Icons.storefront_rounded),
                const SizedBox(width: 12),
                Expanded(child: Text(s.name, style: const TextStyle(fontSize: 16))),
              ]),
            ),
          ),
      ],
    ),
  );
}
