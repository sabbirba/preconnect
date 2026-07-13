import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:preconnect/api/api_config.dart';
import 'package:preconnect/api/notification.dart';
import 'package:preconnect/pages/ui_kit.dart';
import 'package:preconnect/tools/url_utils.dart';

String normalizeCampusPhoneValue(String raw) {
  var value = raw.trim();
  if (value.isEmpty) return '';
  value = value.replaceAll(
    RegExp(r'\s*\(\s*press\s*\d+\s*\)\s*$', caseSensitive: false),
    '',
  );
  value = value.replaceAll(
    RegExp(r'\s*[,;-]?\s*press\s*\d+\s*$', caseSensitive: false),
    '',
  );
  value = value.replaceAll(
    RegExp(r'\s*(ext|extension)\.?\s*\d+.*$', caseSensitive: false),
    '',
  );
  value = value.replaceAll(RegExp(r'[^\d+]'), '');
  return value;
}

class CampusMapData {
  const CampusMapData({
    required this.campusName,
    required this.address,
    required this.mapImageUrl,
    required this.googleMapsUrl,
    required this.sourceUrl,
    required this.transportScheduleUrl,
    required this.images,
    required this.highlights,
    required this.primaryEmail,
    required this.primaryPhone,
    required this.primaryPhoneRaw,
    required this.offices,
    required this.emergencyContacts,
  });

  final String campusName;
  final String address;
  final String mapImageUrl;
  final String googleMapsUrl;
  final String sourceUrl;
  final String transportScheduleUrl;
  final List<String> images;
  final List<String> highlights;
  final String primaryEmail;
  final String primaryPhone;
  final String primaryPhoneRaw;
  final List<CampusOfficeContact> offices;
  final List<CampusEmergencyContact> emergencyContacts;

  factory CampusMapData.fromJson(Map<String, dynamic> json) {
    final sourceUrl = '${json['source_url'] ?? ''}'.trim();
    final contact = json['contact'];
    final contactMap = contact is Map ? contact.cast<String, dynamic>() : null;
    final officeRows = json['general_contacts'];
    final emergencyRows = json['emergency_contacts'];

    final offices = officeRows is List
        ? officeRows
              .whereType<Map>()
              .map((item) => CampusOfficeContact.fromJson(item))
              .toList(growable: false)
        : const <CampusOfficeContact>[];
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
    var images = imagesRaw is List
        ? imagesRaw
              .map((item) {
                if (item is Map) {
                  final map = item.cast<dynamic, dynamic>();
                  return normalizeImageUrl(
                    '${map['url'] ?? map['image_url'] ?? map['src'] ?? ''}',
                    baseUrl: sourceUrl,
                  );
                }
                return normalizeImageUrl('$item', baseUrl: sourceUrl);
              })
              .whereType<String>()
              .toSet()
              .toList(growable: false)
        : const <String>[];
    if (images.isEmpty) {
      final mapImageUrl = normalizeImageUrl(
        '${json['map_image_url'] ?? ''}',
        baseUrl: sourceUrl,
      );
      if (mapImageUrl != null) {
        images = <String>[mapImageUrl];
      }
    }
    final transportRaw = json['transport'];
    final transportMap = transportRaw is Map
        ? transportRaw.cast<String, dynamic>()
        : null;

    String firstValueFromList(dynamic value) {
      if (value is List) {
        for (final item in value) {
          final cleaned = '$item'.trim();
          if (cleaned.isNotEmpty) return cleaned;
        }
      }
      return '';
    }

    String firstPhoneFromList(dynamic value) {
      if (value is List) {
        for (final item in value) {
          final normalized = normalizeCampusPhoneValue('$item');
          if (normalized.isNotEmpty) return normalized;
        }
      }
      return '';
    }

    final primaryEmail = '${contactMap?['email'] ?? ''}'.trim().isNotEmpty
        ? '${contactMap?['email'] ?? ''}'.trim()
        : firstValueFromList(contactMap?['emails']);
    final primaryPhoneRaw =
        '${contactMap?['telephone'] ?? ''}'.trim().isNotEmpty
        ? '${contactMap?['telephone'] ?? ''}'.trim()
        : firstValueFromList(contactMap?['phones']);
    final primaryPhoneFromList = firstPhoneFromList(contactMap?['phones']);
    final primaryPhone = primaryPhoneFromList.isNotEmpty
        ? primaryPhoneFromList
        : normalizeCampusPhoneValue('${contactMap?['telephone'] ?? ''}');

    return CampusMapData(
      campusName: '${json['campus_name'] ?? ''}'.trim(),
      address: '${json['address'] ?? ''}'.trim(),
      mapImageUrl:
          normalizeImageUrl(
            '${json['map_image_url'] ?? ''}',
            baseUrl: sourceUrl,
          ) ??
          '',
      googleMapsUrl: '${json['google_maps_url'] ?? ''}'.trim(),
      sourceUrl: '${json['source_url'] ?? ''}'.trim(),
      transportScheduleUrl: '${json['schedule_url'] ?? ''}'.trim().isNotEmpty
          ? '${json['schedule_url'] ?? ''}'.trim()
          : '${transportMap?['schedule_url'] ?? ''}'.trim(),
      images: images,
      highlights: highlights,
      primaryEmail: primaryEmail,
      primaryPhone: primaryPhone,
      primaryPhoneRaw: primaryPhoneRaw,
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
  });

  final String name;
  final String services;
  final List<String> phones;

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
  bool showContacts = true,
  bool showCallAction = true,
  int collapsedVisibleCount = 5,
}) async {
  var highlightsExpanded = false;
  var officesExpanded = false;
  var emergencyExpanded = false;
  await showBracuBottomSheet<void>(
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
            final sheetScroll = bracuBottomSheetScrollController(context);
            return ListView(
              controller: sheetScroll,
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
          final sheetScroll = bracuBottomSheetScrollController(context);

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
                color: BracuPalette.card(sheetContext).withValues(alpha: 0.7),
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
            children: [
              minimalBlock(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!kIsWeb && mapData.mapImageUrl.isNotEmpty) ...[
                      BracuImageCarousel(
                        imageUrls: <String>[mapData.mapImageUrl],
                        borderRadius: 10,
                        aspectRatio: 16 / 10,
                        imageFit: BoxFit.fitWidth,
                      ),
                      const Gap(10),
                    ],
                    Text(
                      mapData.campusName.isEmpty
                          ? 'BRAC University Campus'
                          : mapData.campusName,
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
                        child: BracuActionButton(
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
                        child: BracuActionButton(
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
                        child: BracuActionButton(
                          iconWidget: const Icon(Icons.email_rounded, size: 16),
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
                        child: BracuActionButton(
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
                      if (showCallAction)
                        SizedBox(
                          width: constraints.maxWidth,
                          child: BracuActionButton(
                            iconWidget: const Icon(
                              Icons.phone_rounded,
                              size: 16,
                            ),
                            label: mapData.primaryPhoneRaw.isEmpty
                                ? 'Call'
                                : mapData.primaryPhoneRaw,
                            onPressed: mapData.primaryPhone.isEmpty
                                ? null
                                : () async {
                                    final normalized =
                                        normalizeCampusPhoneValue(
                                          mapData.primaryPhoneRaw.isEmpty
                                              ? mapData.primaryPhone
                                              : mapData.primaryPhoneRaw,
                                        );
                                    if (normalized.isEmpty) return;
                                    copyToClipboard(sheetContext, normalized);
                                    await openPhoneDialer(
                                      sheetContext,
                                      normalized,
                                    );
                                  },
                          ),
                        ),
                    ],
                  );
                },
              ),
              if (mapData.images.isNotEmpty) ...[
                sectionTitle('Campus Gallery'),
                BracuImageCarousel(imageUrls: mapData.images, borderRadius: 12),
              ],
              if (mapData.highlights.isNotEmpty) ...[
                sectionTitle('Highlights'),
                StatefulBuilder(
                  builder: (context, setLocalState) {
                    final visibleHighlights = highlightsExpanded
                        ? mapData.highlights
                        : mapData.highlights
                              .take(collapsedVisibleCount)
                              .toList(growable: false);
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ...visibleHighlights.map(
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
                                    color: BracuPalette.primary,
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
                        ),
                        if (mapData.highlights.length > collapsedVisibleCount)
                          buildCenteredOutlinedActionButton(
                            label: highlightsExpanded
                                ? 'Show Less'
                                : 'Show More',
                            padding: const EdgeInsets.only(top: 2, bottom: 2),
                            onPressed: () {
                              setLocalState(() {
                                highlightsExpanded = !highlightsExpanded;
                              });
                            },
                          ),
                      ],
                    );
                  },
                ),
              ],
              if (showContacts && mapData.offices.isNotEmpty) ...[
                sectionTitle('General Contacts'),
                StatefulBuilder(
                  builder: (context, setLocalState) {
                    final visibleOffices = officesExpanded
                        ? mapData.offices
                        : mapData.offices
                              .take(collapsedVisibleCount)
                              .toList(growable: false);
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ...visibleOffices.map((office) {
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
                                  ] else ...[
                                    const Gap(4),
                                    Text(
                                      'No email listed',
                                      style: TextStyle(
                                        color: textSecondary,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          );
                        }),
                        if (mapData.offices.length > collapsedVisibleCount)
                          buildCenteredOutlinedActionButton(
                            label: officesExpanded ? 'Show Less' : 'Show More',
                            padding: const EdgeInsets.only(top: 2, bottom: 2),
                            onPressed: () {
                              setLocalState(() {
                                officesExpanded = !officesExpanded;
                              });
                            },
                          ),
                      ],
                    );
                  },
                ),
              ],
              if (showContacts && mapData.emergencyContacts.isNotEmpty) ...[
                sectionTitle('Emergency Contacts'),
                StatefulBuilder(
                  builder: (context, setLocalState) {
                    final visibleEmergency = emergencyExpanded
                        ? mapData.emergencyContacts
                        : mapData.emergencyContacts
                              .take(collapsedVisibleCount)
                              .toList(growable: false);
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ...visibleEmergency.map((item) {
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
                                  if (item.phones.isNotEmpty) ...[
                                    const Gap(6),
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
                                  ] else ...[
                                    const Gap(4),
                                    Text(
                                      'No phone listed',
                                      style: TextStyle(
                                        color: textSecondary,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          );
                        }),
                        if (mapData.emergencyContacts.length >
                            collapsedVisibleCount)
                          buildCenteredOutlinedActionButton(
                            label: emergencyExpanded
                                ? 'Show Less'
                                : 'Show More',
                            padding: const EdgeInsets.only(top: 2, bottom: 2),
                            onPressed: () {
                              setLocalState(() {
                                emergencyExpanded = !emergencyExpanded;
                              });
                            },
                          ),
                      ],
                    );
                  },
                ),
              ],
            ],
          );
        },
      );
    },
  );
}
