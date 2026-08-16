// The Contact page's real contact details (K13).
//
// WHY THIS FILE EXISTS
// The client asked "تواصل معنا" for a logo, a phone number, WhatsApp, an email
// address, social media links and an address. Migration 112 added all six to
// `app_content` and the server has served them since cea459b; the app rendered
// `title` + `body` and nothing else, so the page was one sentence with nothing
// on it to tap.
//
// THE STATE THIS SHIPS IN
// Migration 112 seeded NO values — deliberately, because there is nothing
// anywhere to derive a phone number or an address from. So every one of these
// fields is empty on the day this ships, and the whole design question is what
// "empty" looks like. The answer here is: nothing. No blank row, no dead
// `tel:` link, no WhatsApp button with no number behind it, no card with a
// heading and no contents. A field that has no value is not drawn.
//
// The link builders live in shared/utils/contact_links.dart and return null for
// a value that could not open — that null is what stops an unusable value
// becoming a control that quietly does nothing. Social links go through
// shared/utils/social_links.dart, which already parses this exact column shape
// for partners and City Guide places; migration 112 chose that shape on purpose
// so there would be no third parser.
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:flutter_application_1/core/widgets/app_pressable.dart';
import 'package:flutter_application_1/localization/content_localizer.dart';
import 'package:flutter_application_1/shared/utils/contact_links.dart';
import 'package:flutter_application_1/shared/utils/social_links.dart';
import 'package:flutter_application_1/shared/utils/upload_urls.dart';
import 'package:flutter_application_1/shared/widgets/glass_ui.dart';
import 'package:get/get.dart';

/// The contact columns of one `app_content` row, read once.
///
/// A value object rather than six lookups scattered through a build method, so
/// "is there anything to show?" is one question with one answer — the screen
/// needs it before it decides between drawing this and drawing its empty state.
class ContentContact {
  const ContentContact({
    required this.logoUrl,
    required this.phone,
    required this.whatsapp,
    required this.email,
    required this.socialLinks,
    required this.address,
  });

  /// Reads the contact columns out of a `GET /api/content/:slug` content map.
  ///
  /// The address is localized like every other text column on this table; the
  /// rest are single values a machine acts on, so they are not.
  factory ContentContact.from(Map<String, dynamic> content) {
    return ContentContact(
      logoUrl: uploadedImageUrl(content['logo_path']),
      phone: (content['contact_phone'] ?? '').toString().trim(),
      whatsapp: (content['contact_whatsapp'] ?? '').toString().trim(),
      email: (content['contact_email'] ?? '').toString().trim(),
      socialLinks: socialLinksFrom(content['social_links']),
      address: localizedAppContent(content, 'address'),
    );
  }

  final String? logoUrl;
  final String phone;
  final String whatsapp;
  final String email;
  final List<String> socialLinks;
  final String address;

  /// True when the owner has supplied nothing at all — which is every Contact
  /// page today. The caller draws no contact block whatsoever in that case.
  bool get isEmpty =>
      logoUrl == null &&
      phone.isEmpty &&
      whatsapp.isEmpty &&
      email.isEmpty &&
      socialLinks.isEmpty &&
      address.isEmpty;

  /// Whether the "Contact information" panel has any row to put in it.
  ///
  /// Separate from [isEmpty] because the logo and the social accounts are their
  /// own blocks: a page carrying only a logo must still not draw an empty
  /// details panel above it.
  bool get _hasDetails =>
      phone.isNotEmpty ||
      whatsapp.isNotEmpty ||
      email.isNotEmpty ||
      address.isNotEmpty;
}

/// Draws whichever contact details exist, and nothing for the ones that do not.
class ContentContactCard extends StatelessWidget {
  const ContentContactCard({super.key, required this.contact});

  final ContentContact contact;

  @override
  Widget build(BuildContext context) {
    final logoUrl = contact.logoUrl;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (logoUrl != null) ...[
          Center(
            child: ClipRRect(
              key: const Key('contact_logo'),
              borderRadius: BorderRadius.circular(20),
              child: SizedBox(
                width: 96,
                height: 96,
                child: CachedNetworkImage(
                  imageUrl: logoUrl,
                  fit: BoxFit.cover,
                  fadeInDuration: const Duration(milliseconds: 180),
                  placeholder: (context, url) => _LogoFallback(loading: true),
                  // A logo that will not load falls back to a mark rather than
                  // to a broken-image glyph or an empty hole.
                  errorWidget: (context, url, error) => _LogoFallback(),
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
        ],
        if (contact._hasDetails) ...[
          _Panel(
            key: const Key('contact_details'),
            title: 'Contact information',
            icon: Icons.contact_page_outlined,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ..._phoneRows(
                  rowKey: 'contact_phone',
                  icon: Icons.phone_rounded,
                  label: 'Phone',
                  value: contact.phone,
                  uri: contactDialUri(contact.phone),
                ),
                ..._phoneRows(
                  rowKey: 'contact_whatsapp',
                  icon: Icons.chat_rounded,
                  label: 'whatsapp_open',
                  value: contact.whatsapp,
                  uri: contactWhatsAppUri(contact.whatsapp),
                ),
                ..._phoneRows(
                  rowKey: 'contact_email',
                  icon: Icons.email_rounded,
                  label: 'Email',
                  value: contact.email,
                  uri: contactEmailUri(contact.email),
                ),
                if (contact.address.isNotEmpty)
                  // Read-only on purpose. The address is prose the owner wrote
                  // for a human ("behind the cultural centre"), not a geocoded
                  // place, so a map button on it would open a search that often
                  // finds nothing — which is the same dead control this row
                  // exists to avoid.
                  _DetailRow(
                    key: const Key('contact_address'),
                    icon: Icons.place_rounded,
                    label: 'Address',
                    value: contact.address,
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
        if (contact.socialLinks.isNotEmpty)
          _Panel(
            key: const Key('contact_socials'),
            title: 'Social media accounts',
            icon: Icons.public_rounded,
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final link in contact.socialLinks)
                  _SocialChip(
                    label: socialNetworkLabel(link),
                    onTap: () => openSocialLink(link),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  /// One contact value, as an ACTION when it can open something and as plain
  /// text when it cannot.
  ///
  /// Returns a list so an absent value contributes no widget at all — not an
  /// empty `SizedBox` that still takes a row of spacing.
  ///
  /// The keyed row is always the action. A value the builders refused (prose
  /// where a number should be, from a row written before the server validated
  /// these columns) is still shown, because it is information the owner
  /// published — it simply is not offered as a button that would fail.
  List<Widget> _phoneRows({
    required String rowKey,
    required IconData icon,
    required String label,
    required String value,
    required Uri? uri,
  }) {
    if (value.isEmpty) return const [];
    if (uri == null) {
      return [_DetailRow(icon: icon, label: label, value: value)];
    }
    return [
      _DetailRow(
        key: Key(rowKey),
        icon: icon,
        label: label,
        value: value,
        onTap: () => openContactLink(uri),
      ),
    ];
  }
}

/// A titled panel, matching the partner page's contact block so the two read as
/// the same kind of thing.
class _Panel extends StatelessWidget {
  const _Panel({
    super.key,
    required this.title,
    required this.icon,
    required this.child,
  });

  final String title;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: AppThemeConfig.primary),
              const SizedBox(width: 8),
              Text(
                title.tr,
                style: TextStyle(
                  color: AppThemeConfig.text(context),
                  fontWeight: FontWeight.w900,
                  fontSize: 15,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

/// One labelled contact value. Tappable when [onTap] is given.
class _DetailRow extends StatelessWidget {
  const _DetailRow({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: AppThemeConfig.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label.tr,
                  style: TextStyle(
                    color: AppThemeConfig.mutedText(context),
                    fontWeight: FontWeight.w700,
                    fontSize: 12.5,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  // The value is shown EXACTLY as the owner typed it. A public
                  // number is written for a human to read; reformatting it
                  // would silently disagree with what the dashboard shows.
                  value,
                  // Numbers and addresses are data, so they keep their own
                  // direction inside an Arabic page rather than being mirrored.
                  textDirection: TextDirection.ltr,
                  textAlign: TextAlign.start,
                  style: TextStyle(
                    color: AppThemeConfig.text(context),
                    fontWeight: FontWeight.w800,
                    fontSize: 14.5,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          if (onTap != null)
            Icon(
              Icons.open_in_new_rounded,
              size: 16,
              color: AppThemeConfig.mutedText(context),
            ),
        ],
      ),
    );

    if (onTap == null) return row;
    return AppPressable(
      onTap: onTap,
      expand: true,
      haptic: AppPressHaptic.selection,
      semanticLabel: '${label.tr}: $value',
      child: row,
    );
  }
}

/// One social account, named by its network rather than by its URL (K17).
class _SocialChip extends StatelessWidget {
  const _SocialChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AppPressable(
      onTap: onTap,
      haptic: AppPressHaptic.selection,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppThemeConfig.primary.withValues(alpha: 0.11),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppThemeConfig.border(context)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.public_rounded,
              size: 17,
              color: AppThemeConfig.primary,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: AppThemeConfig.text(context),
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Stands in for the logo while it loads and when it will not load at all.
class _LogoFallback extends StatelessWidget {
  const _LogoFallback({this.loading = false});

  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppThemeConfig.surface(context),
      alignment: Alignment.center,
      child: loading
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator.adaptive(strokeWidth: 2),
            )
          : Icon(
              Icons.apartment_rounded,
              size: 28,
              color: AppThemeConfig.mutedText(context),
            ),
    );
  }
}
