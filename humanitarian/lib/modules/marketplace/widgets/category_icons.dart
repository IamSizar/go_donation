// #41080 — fixed icon vocabulary for marketplace_categories.icon_key, kept
// in lockstep with the backend's marketplacecategories.ValidIconKeys (Go)
// and the admin dashboard's ICON_OPTIONS (admin-web/.../MarketplaceCategoriesPage.tsx).
// Add a key to all three together, never just one.
import 'package:flutter/material.dart';

/// Maps a category's `icon_key` to the Material icon the store grid draws
/// for it. An unrecognised key (a value added on one side but not yet
/// shipped to the app) falls back to the same glyph as "other" rather than
/// throwing or rendering blank.
IconData categoryIconFor(String? iconKey) => switch (iconKey) {
  'food' => Icons.restaurant_rounded,
  'groceries' => Icons.shopping_basket_rounded,
  'clothing' => Icons.checkroom_rounded,
  'accessories' => Icons.watch_rounded,
  'electronics' => Icons.devices_rounded,
  'home' => Icons.home_rounded,
  'beauty' => Icons.auto_awesome_rounded,
  'toys' => Icons.toys_rounded,
  'books' => Icons.menu_book_rounded,
  'health' => Icons.favorite_rounded,
  'sports' => Icons.fitness_center_rounded,
  'tools' => Icons.build_rounded,
  'gifts' => Icons.card_giftcard_rounded,
  'pets' => Icons.pets_rounded,
  'stationery' => Icons.edit_rounded,
  _ => Icons.inventory_2_rounded,
};
