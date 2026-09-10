import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:preconnect/api/api_config.dart';
import 'package:preconnect/api/notification.dart';
import 'package:preconnect/pages/ui_kit.dart';
import 'package:preconnect/tools/url_utils.dart';

final _pressExtRegex = RegExp(
  r'\s*\(\s*press\s*\d+\s*\)\s*$',
  caseSensitive: false,
);
final _pressSuffixRegex = RegExp(
  r'\s*[,;-]?\s*press\s*\d+\s*$',
  caseSensitive: false,
);
final _extensionSuffixRegex = RegExp(
  r'\s*(ext|extension)\.?\s*\d+.*$',
  caseSensitive: false,
);
final _nonPhoneCharRegex = RegExp(r'[^\d+]');

String normalizeCampusPhoneValue(String raw) {
  var value = raw.trim();
  if (value.isEmpty) return '';
  value = value.replaceAll(_pressExtRegex, '');
  value = value.replaceAll(_pressSuffixRegex, '');
  value = value.replaceAll(_extensionSuffixRegex, '');
  value = value.replaceAll(_nonPhoneCharRegex, '');
  return value;
}

class CampusMapData {
  const CampusMapData({
    required this.campusName,
    required this.address,
    required this.summary,
    required this.mapImageUrl,
    required this.googleMapsUrl,
    required this.sourceUrl,
    required this.transportScheduleUrl,
    required this.primaryEmail,
    required this.images,
    required this.highlights,
    required this.offices,
    required this.emergencyContacts,
  });

  final String campusName;
  final String address;
  final String summary;
  final String mapImageUrl;
  final String googleMapsUrl;
  final String sourceUrl;
  final String transportScheduleUrl;
  final String primaryEmail;
  final List<String> images;
  final List<String> highlights;
  final List<CampusOfficeContact> offices;
  final List<CampusEmergencyContact> emergencyContacts;

  factory CampusMapData.fromJson(Map<String, dynamic> json) {
    final sourceUrl = '${json['source_url'] ?? ''}'.trim();
    final officeRows = json['general_contacts'];
    final emergencyRows = json['emergency_contacts'];

    final offices = officeRows is List
        ? officeRows
              .whereType<Map>()
              .map((item) => CampusOfficeContact.fromJson(item))
              .toList(growable: true)
        : <CampusOfficeContact>[];
    final emergencies = emergencyRows is List
        ? emergencyRows
              .whereType<Map>()
              .map((item) => CampusEmergencyContact.fromJson(item))
              .toList(growable: false)
        : const <CampusEmergencyContact>[];

    final highlightsRaw = json['highlights'];
    final highlights = highlightsRaw is List
        ? highlightsRaw
              .map((item) => '$item'.trim())
              .where((item) => item.isNotEmpty)
              .toList(growable: false)
        : const <String>[];

    final imagesRaw = json['images'];
    final images = imagesRaw is List
        ? imagesRaw
              .map((item) => normalizeImageUrl('$item', baseUrl: sourceUrl))
              .whereType<String>()
              .toList(growable: false)
        : const <String>[];

    const primaryEmail = 'info@bracu.ac.bd';

    return CampusMapData(
      campusName: '${json['campus_name'] ?? ''}'.trim(),
      address: '${json['address'] ?? ''}'.trim(),
      summary: '${json['summary'] ?? ''}'.trim(),
      mapImageUrl:
          normalizeImageUrl(
            '${json['map_image_url'] ?? ''}',
            baseUrl: sourceUrl,
          ) ??
          '',
      googleMapsUrl: '${json['google_maps_url'] ?? ''}'.trim(),
      sourceUrl: '${json['source_url'] ?? ''}'.trim(),
      transportScheduleUrl: '${json['schedule_url'] ?? ''}'.trim(),
      primaryEmail: primaryEmail,
      images: images,
      highlights: highlights,
      offices: offices,
      emergencyContacts: emergencies,
    );
  }
}

class CampusOfficeContact {
  const CampusOfficeContact({required this.office, required this.emails});

  final String office;
  final List<String> emails;

  factory CampusOfficeContact.fromJson(Map<dynamic, dynamic> json) {
    final rawEmails = json['emails'];
    return CampusOfficeContact(
      office: '${json['office'] ?? ''}'.trim(),
      emails: rawEmails is List
          ? rawEmails
                .map((item) => '$item'.trim())
                .where((item) => item.isNotEmpty)
                .toList(growable: false)
          : const <String>[],
    );
  }
}

class CampusEmergencyContact {
  const CampusEmergencyContact({
    required this.name,
    required this.services,
    required this.phones,
    this.email = '',
    this.hours = '',
  });

  final String name;
  final String services;
  final List<String> phones;
  final String email;
  final String hours;

  factory CampusEmergencyContact.fromJson(Map<dynamic, dynamic> json) {
    final rawPhones = json['phones'];
    return CampusEmergencyContact(
      name: '${json['name'] ?? ''}'.trim(),
      services: '${json['services'] ?? ''}'.trim(),
      phones: rawPhones is List
          ? rawPhones
                .map((item) => '$item'.trim())
                .where((item) => item.isNotEmpty)
                .toList(growable: false)
          : const <String>[],
      email: '${json['email'] ?? ''}'.trim(),
      hours: '${json['hours'] ?? ''}'.trim(),
    );
  }
}

void _prewarmImages(List<String> urls) {
  for (final url in urls) {
    if (url.trim().isNotEmpty) {
      unawaited(
        DefaultCacheManager()
            .getSingleFile(url.trim())
            .then((_) {}, onError: (_) {}),
      );
    }
  }
}

Future<CampusMapData?> fetchCampusMapData({bool forceRefresh = false}) async {
  final payload = await ScraperDataService().fetchMap(
    path: ApiConfig.campusMapUrl,
    cacheKey: 'scraper_campus_map_v1',
    ttl: const Duration(hours: 12),
    forceRefresh: forceRefresh,
  );
  if (payload == null) return null;
  final parsed = CampusMapData.fromJson(payload);
  final List<String> toWarm = [];
  if (parsed.mapImageUrl.isNotEmpty) toWarm.add(parsed.mapImageUrl);
  if (parsed.images.isNotEmpty) toWarm.addAll(parsed.images.take(3));
  _prewarmImages(toWarm);

  final hasAnyImage = parsed.mapImageUrl.isNotEmpty || parsed.images.isNotEmpty;
  if (hasAnyImage || forceRefresh) return parsed;

  final freshPayload = await ScraperDataService().fetchMap(
    path: ApiConfig.campusMapUrl,
    cacheKey: 'scraper_campus_map_v1',
    ttl: const Duration(hours: 12),
    forceRefresh: true,
  );
  if (freshPayload == null) return parsed;
  final freshParsed = CampusMapData.fromJson(freshPayload);
  final List<String> freshToWarm = [];
  if (freshParsed.mapImageUrl.isNotEmpty) {
    freshToWarm.add(freshParsed.mapImageUrl);
  }
  if (freshParsed.images.isNotEmpty) {
    freshToWarm.addAll(freshParsed.images.take(3));
  }
  _prewarmImages(freshToWarm);
  return freshParsed;
}

Future<String?> fetchTransportScheduleUrl({bool forceRefresh = false}) async {
  final rows = await ScraperDataService().fetchList(
    path: ApiConfig.transportUrl,
    cacheKey: 'scraper_transport_v1',
    ttl: const Duration(hours: 12),
    forceRefresh: forceRefresh,
  );
  for (final row in rows) {
    final url = '${row['schedule_url'] ?? ''}'.trim();
    if (url.isNotEmpty) return url;
  }
  return null;
}

Future<void> showCampusMapBottomSheet(
  BuildContext context, {
  required Future<CampusMapData?> campusMapFuture,
  required Future<String?> transportScheduleUrlFuture,
}) async {
  await showAppBottomSheet<void>(
    context,
    title: 'Campus Map',
    subtitle: 'Directions, highlights and key contacts',
    builder: (sheetContext, textPrimary, textSecondary) {
      return FutureBuilder<List<dynamic>>(
        future: Future.wait<dynamic>([
          campusMapFuture,
          transportScheduleUrlFuture,
        ]),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const SizedBox.shrink();
          }
          final values = snapshot.data;
          final mapData = values != null && values.isNotEmpty
              ? values[0] as CampusMapData?
              : null;
          final transportScheduleUrl = values != null && values.length > 1
              ? (values[1] as String?)
              : null;
          if (mapData == null) {
            final sheetScroll = bottomSheetScrollController(context);
            return ListView(
              controller: sheetScroll,
              physics: const ClampingScrollPhysics(),
              children: [
                Text(
                  'Campus map data is unavailable right now.',
                  style: TextStyle(
                    color: textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            );
          }
          final sheetScroll = bottomSheetScrollController(context);

          Widget sectionTitle(String value) => Padding(
            padding: const EdgeInsets.only(top: 16, bottom: 8),
            child: Text(
              value,
              style: TextStyle(
                color: textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.2,
              ),
            ),
          );

          Widget minimalBlock({required Widget child}) {
            return Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppPalette.card(sheetContext).withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: textSecondary.withValues(alpha: 0.16),
                ),
              ),
              child: child,
            );
          }

          final resolvedTransportUrl =
              transportScheduleUrl != null &&
                  transportScheduleUrl.trim().isNotEmpty
              ? transportScheduleUrl.trim()
              : mapData.transportScheduleUrl;
          return ListView(
            controller: sheetScroll,
            physics: const ClampingScrollPhysics(),
            children: [
              minimalBlock(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!kIsWeb && mapData.mapImageUrl.isNotEmpty) ...[
                      ImageCarousel(
                        imageUrls: <String>[mapData.mapImageUrl],
                        borderRadius: 10,
                        aspectRatio: 16 / 10,
                        imageFit: BoxFit.fitWidth,
                      ),
                      const Gap(12),
                    ],
                    Text(
                      mapData.campusName,
                      style: TextStyle(
                        color: textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (mapData.address.isNotEmpty) ...[
                      const Gap(6),
                      Text(
                        mapData.address,
                        style: TextStyle(
                          color: textSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const Gap(12),
              LayoutBuilder(
                builder: (context, constraints) {
                  const gap = 8.0;
                  final buttonWidth = (constraints.maxWidth - gap) / 2;
                  return Wrap(
                    spacing: gap,
                    runSpacing: gap,
                    children: [
                      SizedBox(
                        width: buttonWidth,
                        child: AppActionButton(
                          icon: Icons.directions_rounded,
                          label: 'Open Map',
                          onPressed: mapData.googleMapsUrl.isEmpty
                              ? null
                              : () => openExternalUrl(
                                  sheetContext,
                                  mapData.googleMapsUrl,
                                ),
                        ),
                      ),
                      SizedBox(
                        width: buttonWidth,
                        child: AppActionButton(
                          icon: Icons.open_in_new_rounded,
                          label: 'Campus Life',
                          onPressed: mapData.sourceUrl.isEmpty
                              ? null
                              : () => openExternalUrl(
                                  sheetContext,
                                  mapData.sourceUrl,
                                ),
                        ),
                      ),
                      SizedBox(
                        width: buttonWidth,
                        child: AppActionButton(
                          icon: Icons.email_rounded,
                          label: 'Email',
                          onPressed: mapData.primaryEmail.isEmpty
                              ? null
                              : () => openMailComposer(
                                  sheetContext,
                                  mapData.primaryEmail,
                                ),
                        ),
                      ),
                      SizedBox(
                        width: buttonWidth,
                        child: AppActionButton(
                          icon: Icons.directions_bus_rounded,
                          label: 'Transport',
                          onPressed: resolvedTransportUrl.isEmpty
                              ? null
                              : () => openExternalUrl(
                                  sheetContext,
                                  resolvedTransportUrl,
                                ),
                        ),
                      ),
                    ],
                  );
                },
              ),
              if (mapData.summary.isNotEmpty) ...[
                sectionTitle('About Campus'),
                minimalBlock(
                  child: Text(
                    mapData.summary,
                    style: TextStyle(
                      color: textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      height: 1.45,
                    ),
                  ),
                ),
              ],
              if (mapData.images.isNotEmpty) ...[
                sectionTitle('Campus Gallery'),
                ImageCarousel(imageUrls: mapData.images, borderRadius: 12),
              ],
              if (mapData.highlights.isNotEmpty) ...[
                sectionTitle('Highlights'),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: mapData.highlights
                      .map(
                        (item) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Icon(
                                  Icons.circle,
                                  size: 6,
                                  color: AppPalette.primary,
                                ),
                              ),
                              const Gap(8),
                              Expanded(
                                child: Text(
                                  item,
                                  style: TextStyle(
                                    color: textSecondary,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                    height: 1.35,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                      .toList(growable: false),
                ),
              ],
              if (mapData.emergencyContacts.isNotEmpty) ...[
                sectionTitle('Emergency Contacts'),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: mapData.emergencyContacts
                      .map((item) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: minimalBlock(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.name,
                                  style: TextStyle(
                                    color: textPrimary,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                if (item.services.isNotEmpty) ...[
                                  const Gap(2),
                                  Text(
                                    item.services,
                                    style: TextStyle(
                                      color: textSecondary,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                                if (item.hours.isNotEmpty) ...[
                                  const Gap(4),
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.schedule_rounded,
                                        size: 13,
                                        color: textSecondary,
                                      ),
                                      const Gap(4),
                                      Text(
                                        item.hours,
                                        style: TextStyle(
                                          color: textSecondary,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                                if (item.email.isNotEmpty) ...[
                                  const Gap(4),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          item.email,
                                          style: TextStyle(
                                            color: textSecondary,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ),
                                      IconButton(
                                        onPressed: () => openMailComposer(
                                          sheetContext,
                                          item.email,
                                        ),
                                        icon: const Icon(
                                          Icons.email_rounded,
                                          size: 16,
                                        ),
                                        tooltip: 'Email',
                                      ),
                                    ],
                                  ),
                                ],
                                if (item.phones.isNotEmpty) ...[
                                  const Gap(4),
                                  ...item.phones.map(
                                    (phone) => Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            phone,
                                            style: TextStyle(
                                              color: textSecondary,
                                              fontSize: 11,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ),
                                        IconButton(
                                          onPressed: () async {
                                            final normalized =
                                                normalizeCampusPhoneValue(
                                                  phone,
                                                );
                                            if (normalized.isEmpty) return;
                                            copyToClipboard(
                                              sheetContext,
                                              normalized,
                                            );
                                            await openPhoneDialer(
                                              sheetContext,
                                              normalized,
                                            );
                                          },
                                          icon: const Icon(
                                            Icons.phone_rounded,
                                            size: 18,
                                          ),
                                          tooltip: 'Call',
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        );
                      })
                      .toList(growable: false),
                ),
              ],
              if (mapData.offices.isNotEmpty) ...[
                sectionTitle('General Contacts'),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: mapData.offices
                      .map((office) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: minimalBlock(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  office.office,
                                  style: TextStyle(
                                    color: textPrimary,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                if (office.emails.isNotEmpty) ...[
                                  const Gap(6),
                                  ...office.emails.map(
                                    (email) => Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            email,
                                            style: TextStyle(
                                              color: textSecondary,
                                              fontSize: 11,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ),
                                        IconButton(
                                          onPressed: () => openMailComposer(
                                            sheetContext,
                                            email,
                                          ),
                                          icon: const Icon(
                                            Icons.email_rounded,
                                            size: 16,
                                          ),
                                          tooltip: 'Email',
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        );
                      })
                      .toList(growable: false),
                ),
              ],
            ],
          );
        },
      );
    },
  );
}
