import 'package:flutter/material.dart';

import '../models/ods_style_hint.dart';

/// Translates abstract [OdsStyleHint] values into concrete Flutter styles.
///
/// ODS Spec alignment: The spec defines styleHint as an open-ended object.
/// This resolver interprets the known hint keys:
///   - `variant`: text → "heading"/"subheading"/"body"/"caption";
///                button → "filled"/"outlined"/"text"/"tonal"
///   - `emphasis`: "primary", "secondary", "danger"
///   - `color`: semantic or named accent color
///   - `icon`: Material icon name
///   - `align`: "left", "center", "right"
///   - `size`: "compact", "default", "large"
///   - `density`: "compact", "default", "comfortable"
///   - `elevation`: 0–3
///
/// Unknown hints are ignored, keeping forward compatibility.
///
/// ODS Ethos: StyleHints are suggestions, not pixel-perfect instructions.
/// The framework maps them to Material Design tokens so the app looks
/// native on every platform. The spec author says "this is a heading" —
/// they don't choose font sizes or colors. Simple for the author,
/// polished for the user.
class StyleResolver {
  const StyleResolver();

  // ---------------------------------------------------------------------------
  // Color resolution — the foundation for accent-tinted components
  // ---------------------------------------------------------------------------

  /// Maps a color hint name to a Material [Color].
  ///
  /// Supports semantic names (adapt to theme) and explicit named colors.
  /// Returns null for unrecognized values — callers fall back to defaults.
  Color? resolveColor(String? colorName, BuildContext context) {
    if (colorName == null) return null;
    final cs = Theme.of(context).colorScheme;

    switch (colorName.toLowerCase()) {
      // Semantic colors — adapt to theme
      case 'primary':
        return cs.primary;
      case 'secondary':
        return cs.secondary;
      case 'tertiary':
        return cs.tertiary;
      case 'success':
        return const Color(0xFF16A34A); // green-600
      case 'warning':
        return const Color(0xFFD97706); // amber-600
      case 'error':
        return cs.error;
      case 'info':
        return const Color(0xFF2563EB); // blue-600

      // Named colors — explicit and predictable
      case 'green':
        return const Color(0xFF16A34A);
      case 'red':
        return const Color(0xFFDC2626);
      case 'blue':
        return const Color(0xFF2563EB);
      case 'orange':
        return const Color(0xFFEA580C);
      case 'purple':
        return const Color(0xFF9333EA);
      case 'teal':
        return const Color(0xFF0D9488);
      case 'pink':
        return const Color(0xFFDB2777);
      case 'amber':
        return const Color(0xFFD97706);
      case 'indigo':
        return const Color(0xFF4F46E5);
      case 'grey':
      case 'gray':
        return const Color(0xFF6B7280);

      default:
        return null;
    }
  }

  /// Returns a light tint of the accent color (for card backgrounds, etc.).
  Color? resolveColorTint(String? colorName, BuildContext context) {
    final base = resolveColor(colorName, context);
    if (base == null) return null;
    final brightness = Theme.of(context).brightness;
    return brightness == Brightness.light
        ? base.withValues(alpha: 0.08)
        : base.withValues(alpha: 0.15);
  }

  // ---------------------------------------------------------------------------
  // Icon resolution
  // ---------------------------------------------------------------------------

  /// Maps an icon name string to a Material [IconData].
  ///
  /// Supports the most common Material icon names. Returns null for
  /// unrecognized names — callers can fall back or skip the icon.
  static IconData? resolveIcon(String? iconName) {
    if (iconName == null) return null;
    return _iconMap[iconName.toLowerCase()];
  }

  /// Master icon map — intentionally comprehensive for builder convenience.
  static const Map<String, IconData> _iconMap = {
    // Navigation & actions
    'add': Icons.add,
    'add_circle': Icons.add_circle_outline,
    'arrow_back': Icons.arrow_back,
    'arrow_forward': Icons.arrow_forward,
    'check': Icons.check,
    'check_circle': Icons.check_circle_outline,
    'close': Icons.close,
    'delete': Icons.delete_outline,
    'edit': Icons.edit_outlined,
    'menu': Icons.menu,
    'more': Icons.more_horiz,
    'refresh': Icons.refresh,
    'save': Icons.save_outlined,
    'search': Icons.search,
    'send': Icons.send_outlined,
    'share': Icons.share_outlined,
    'upload': Icons.upload_outlined,
    'download': Icons.download_outlined,
    'copy': Icons.copy_outlined,
    'undo': Icons.undo,
    'redo': Icons.redo,
    'filter': Icons.filter_list,
    'sort': Icons.sort,
    'settings': Icons.settings_outlined,
    'tune': Icons.tune,

    // Status & feedback
    'info': Icons.info_outline,
    'warning': Icons.warning_amber_outlined,
    'error': Icons.error_outline,
    'help': Icons.help_outline,
    'star': Icons.star_outline,
    'star_filled': Icons.star,
    'favorite': Icons.favorite_outline,
    'favorite_filled': Icons.favorite,
    'thumb_up': Icons.thumb_up_outlined,
    'thumb_down': Icons.thumb_down_outlined,
    'flag': Icons.flag_outlined,
    'bookmark': Icons.bookmark_outline,
    'bookmark_filled': Icons.bookmark,
    'done': Icons.done,
    'done_all': Icons.done_all,
    'cancel': Icons.cancel_outlined,
    'block': Icons.block,
    'verified': Icons.verified_outlined,

    // Content & data
    'list': Icons.list,
    'grid': Icons.grid_view,
    'table': Icons.table_chart_outlined,
    'chart': Icons.bar_chart,
    'pie_chart': Icons.pie_chart_outline,
    'trending_up': Icons.trending_up,
    'trending_down': Icons.trending_down,
    'trending_flat': Icons.trending_flat,
    'analytics': Icons.analytics_outlined,
    'dashboard': Icons.dashboard_outlined,
    'description': Icons.description_outlined,
    'article': Icons.article_outlined,
    'note': Icons.note_outlined,
    'folder': Icons.folder_outlined,
    'file': Icons.insert_drive_file_outlined,
    'image': Icons.image_outlined,
    'photo': Icons.photo_outlined,
    'camera': Icons.camera_alt_outlined,
    'attachment': Icons.attach_file,
    'link': Icons.link,

    // People & communication
    'person': Icons.person_outline,
    'people': Icons.people_outline,
    'group': Icons.group_outlined,
    'chat': Icons.chat_outlined,
    'email': Icons.email_outlined,
    'phone': Icons.phone_outlined,
    'notification': Icons.notifications_outlined,
    'message': Icons.message_outlined,
    'forum': Icons.forum_outlined,

    // Commerce & finance
    'shopping_cart': Icons.shopping_cart_outlined,
    'shopping_bag': Icons.shopping_bag_outlined,
    'store': Icons.store_outlined,
    'payment': Icons.payment_outlined,
    'receipt': Icons.receipt_outlined,
    'attach_money': Icons.attach_money,
    'money': Icons.attach_money,
    'credit_card': Icons.credit_card,
    'account_balance': Icons.account_balance_outlined,
    'wallet': Icons.wallet_outlined,

    // Time & scheduling
    'calendar': Icons.calendar_today_outlined,
    'schedule': Icons.schedule,
    'timer': Icons.timer_outlined,
    'alarm': Icons.alarm,
    'history': Icons.history,
    'event': Icons.event_outlined,
    'today': Icons.today,
    'date_range': Icons.date_range,

    // Places & travel
    'home': Icons.home_outlined,
    'location': Icons.location_on_outlined,
    'map': Icons.map_outlined,
    'directions': Icons.directions_outlined,
    'flight': Icons.flight_outlined,
    'hotel': Icons.hotel_outlined,
    'restaurant': Icons.restaurant_outlined,
    'local_cafe': Icons.local_cafe_outlined,
    'local_grocery': Icons.local_grocery_store_outlined,

    // Categories & objects
    'tag': Icons.label_outlined,
    'label': Icons.label_outlined,
    'category': Icons.category_outlined,
    'inventory': Icons.inventory_2_outlined,
    'package': Icons.inventory_2_outlined,
    'build': Icons.build_outlined,
    'science': Icons.science_outlined,
    'palette': Icons.palette_outlined,
    'brush': Icons.brush_outlined,

    // Health & wellness
    'health': Icons.health_and_safety_outlined,
    'fitness': Icons.fitness_center_outlined,
    'mood': Icons.mood_outlined,
    'mood_bad': Icons.mood_bad_outlined,
    'psychology': Icons.psychology_outlined,
    'self_improvement': Icons.self_improvement_outlined,
    'spa': Icons.spa_outlined,

    // Education & learning
    'school': Icons.school_outlined,
    'book': Icons.menu_book_outlined,
    'library': Icons.local_library_outlined,
    'quiz': Icons.quiz_outlined,
    'lightbulb': Icons.lightbulb_outline,
    'extension': Icons.extension_outlined,

    // Misc
    'checklist': Icons.checklist,
    'task': Icons.task_outlined,
    'assignment': Icons.assignment_outlined,
    'clipboard': Icons.content_paste,
    'trophy': Icons.emoji_events_outlined,
    'celebration': Icons.celebration_outlined,
    'rocket': Icons.rocket_launch_outlined,
    'speed': Icons.speed,
    'bolt': Icons.bolt,
    'eco': Icons.eco_outlined,
    'pets': Icons.pets,
    'music': Icons.music_note_outlined,
    'movie': Icons.movie_outlined,
    'sports': Icons.sports_outlined,
    'security': Icons.security_outlined,
    'lock': Icons.lock_outlined,
    'key': Icons.key_outlined,
    'visibility': Icons.visibility_outlined,
    'visibility_off': Icons.visibility_off_outlined,
    'language': Icons.language,
    'code': Icons.code,
    'terminal': Icons.terminal,
    'cloud': Icons.cloud_outlined,
    'print': Icons.print_outlined,
    'qr_code': Icons.qr_code,
  };

  // ---------------------------------------------------------------------------
  // Alignment resolution
  // ---------------------------------------------------------------------------

  /// Maps an align hint to a Flutter [TextAlign].
  TextAlign resolveTextAlign(OdsStyleHint hint) {
    switch (hint.align) {
      case 'center':
        return TextAlign.center;
      case 'right':
        return TextAlign.right;
      case 'left':
      default:
        return TextAlign.left;
    }
  }

  /// Maps an align hint to a [CrossAxisAlignment] for row/column layouts.
  CrossAxisAlignment resolveCrossAlignment(OdsStyleHint hint) {
    switch (hint.align) {
      case 'center':
        return CrossAxisAlignment.center;
      case 'right':
        return CrossAxisAlignment.end;
      case 'left':
      default:
        return CrossAxisAlignment.start;
    }
  }

  // ---------------------------------------------------------------------------
  // Text style resolution
  // ---------------------------------------------------------------------------

  /// Maps a text variant hint to a Material [TextStyle], with optional
  /// color and alignment overrides from the style hint.
  TextStyle resolveTextStyle(OdsStyleHint hint, BuildContext context) {
    final theme = Theme.of(context).textTheme;

    TextStyle base;
    switch (hint.variant) {
      case 'heading':
        base = theme.headlineMedium ?? const TextStyle(fontSize: 24, fontWeight: FontWeight.bold);
      case 'subheading':
        base = theme.titleMedium ?? const TextStyle(fontSize: 18, fontWeight: FontWeight.w500);
      case 'caption':
        base = theme.bodySmall ?? const TextStyle(fontSize: 12, color: Colors.grey);
      case 'body':
      default:
        base = theme.bodyLarge ?? const TextStyle(fontSize: 16);
    }

    // Apply color hint.
    final accentColor = resolveColor(hint.color, context);
    if (accentColor != null) {
      base = base.copyWith(color: accentColor);
    }

    return base;
  }

  // ---------------------------------------------------------------------------
  // Button style resolution
  // ---------------------------------------------------------------------------

  /// Resolves a complete button style from emphasis, variant, color, and size.
  ///
  /// Button variants:
  ///   - "filled" (default) → ElevatedButton with solid background
  ///   - "outlined" → bordered, transparent background
  ///   - "text" → no border, no background, just text
  ///   - "tonal" → muted filled with tint
  ButtonStyle resolveButtonStyle(OdsStyleHint hint, BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final variant = hint.get<String>('variant') ?? 'filled';

    // Determine the accent color from emphasis or explicit color.
    Color bgColor;
    Color fgColor;
    switch (hint.emphasis) {
      case 'primary':
        bgColor = cs.primary;
        fgColor = cs.onPrimary;
      case 'secondary':
        bgColor = cs.secondary;
        fgColor = cs.onSecondary;
      case 'danger':
        bgColor = cs.error;
        fgColor = cs.onError;
      default:
        bgColor = cs.primary;
        fgColor = cs.onPrimary;
    }

    // Explicit color overrides emphasis.
    final accentColor = resolveColor(hint.color, context);
    if (accentColor != null) {
      bgColor = accentColor;
      // Pick a foreground that contrasts against the accent.
      fgColor = accentColor.computeLuminance() > 0.5
          ? Colors.black87
          : Colors.white;
    }

    // Size-dependent padding.
    final padding = switch (hint.size) {
      'compact' => const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      'large' => const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
      _ => const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
    };

    // Size-dependent text scale.
    final textStyle = switch (hint.size) {
      'compact' => const TextStyle(fontSize: 13),
      'large' => const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      _ => null,
    };

    switch (variant) {
      case 'outlined':
        return OutlinedButton.styleFrom(
          foregroundColor: bgColor,
          side: BorderSide(color: bgColor, width: 1.5),
          padding: padding,
          textStyle: textStyle,
        );

      case 'text':
        return TextButton.styleFrom(
          foregroundColor: bgColor,
          padding: padding,
          textStyle: textStyle,
        );

      case 'tonal':
        final brightness = Theme.of(context).brightness;
        final tintBg = brightness == Brightness.light
            ? bgColor.withValues(alpha: 0.12)
            : bgColor.withValues(alpha: 0.24);
        return ElevatedButton.styleFrom(
          backgroundColor: tintBg,
          foregroundColor: bgColor,
          elevation: 0,
          padding: padding,
          textStyle: textStyle,
        );

      case 'filled':
      default:
        // No emphasis specified → use default theme styling (no forced colors).
        if (hint.emphasis == null && accentColor == null) {
          return ElevatedButton.styleFrom(
            padding: padding,
            textStyle: textStyle,
          );
        }
        return ElevatedButton.styleFrom(
          backgroundColor: bgColor,
          foregroundColor: fgColor,
          padding: padding,
          textStyle: textStyle,
        );
    }
  }

  /// Returns true if the button variant implies an outlined or text button
  /// (not filled), which changes the widget type in the renderer.
  bool isOutlinedVariant(OdsStyleHint hint) {
    final v = hint.get<String>('variant');
    return v == 'outlined';
  }

  bool isTextVariant(OdsStyleHint hint) {
    final v = hint.get<String>('variant');
    return v == 'text';
  }
}
