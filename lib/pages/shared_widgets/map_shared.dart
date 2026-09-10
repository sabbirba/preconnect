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

class CampusProfile {
  const CampusProfile({
    this.landAreaAcres,
    this.buildingAreaSqft,
    this.buildingFloors,
    this.basements,
    this.studentCapacityMin,
    this.studentCapacityMax,
  });

  final num? landAreaAcres;
  final int? buildingAreaSqft;
  final int? buildingFloors;
  final int? basements;
  final int? studentCapacityMin;
  final int? studentCapacityMax;

  bool get hasData =>
      landAreaAcres != null ||
      buildingAreaSqft != null ||
      buildingFloors != null ||
      basements != null ||
      studentCapacityMin != null ||
      studentCapacityMax != null;

  factory CampusProfile.fromJson(Map<dynamic, dynamic> json) {
    num? parseNum(dynamic v) {
      if (v is num) return v;
      if (v == null) return null;
      return num.tryParse('$v'.replaceAll(',', '').trim());
    }

    int? parseInt(dynamic v) {
      if (v is int) return v;
      if (v is num) return v.toInt();
      if (v == null) return null;
      return int.tryParse('$v'.replaceAll(',', '').trim());
    }

    final cap = json['student_capacity'];
    final capMap = cap is Map ? cap : null;

    return CampusProfile(
      landAreaAcres: parseNum(json['land_area_acres']),
      buildingAreaSqft: parseInt(json['building_area_sqft']),
      buildingFloors: parseInt(json['building_floors']),
      basements: parseInt(json['basements']),
      studentCapacityMin: parseInt(
        capMap?['min'] ?? json['student_capacity_min'],
      ),
      studentCapacityMax: parseInt(
        capMap?['max'] ?? json['student_capacity_max'],
      ),
    );
  }
}

class CampusFacilities {
  const CampusFacilities({
    this.classrooms,
    this.lectureTheatres,
    this.laboratories,
    this.libraryBooks,
    this.libraryHasArVr = false,
  });

  final int? classrooms;
  final int? lectureTheatres;
  final int? laboratories;
  final int? libraryBooks;
  final bool libraryHasArVr;

  bool get hasData =>
      classrooms != null ||
      lectureTheatres != null ||
      laboratories != null ||
      libraryBooks != null ||
      libraryHasArVr;

  factory CampusFacilities.fromJson(Map<dynamic, dynamic> json) {
    int? parseInt(dynamic v) {
      if (v is int) return v;
      if (v is num) return v.toInt();
      if (v == null) return null;
      return int.tryParse('$v'.replaceAll(',', '').trim());
    }

    return CampusFacilities(
      classrooms: parseInt(json['classrooms']),
      lectureTheatres: parseInt(json['lecture_theatres']),
      laboratories: parseInt(json['laboratories']),
      libraryBooks: parseInt(json['library_books']),
      libraryHasArVr: json['library_has_ar_vr'] == true,
    );
  }
}

class CampusSustainability {
  const CampusSustainability({
    this.rainwaterWaterDemandPercent,
    this.solarEnergyDemandPercent,
  });

  final num? rainwaterWaterDemandPercent;
  final num? solarEnergyDemandPercent;

  bool get hasData =>
      rainwaterWaterDemandPercent != null || solarEnergyDemandPercent != null;

  factory CampusSustainability.fromJson(Map<dynamic, dynamic> json) {
    num? parseNum(dynamic v) {
      if (v is num) return v;
      if (v == null) return null;
      return num.tryParse('$v'.replaceAll(',', '').trim());
    }

    return CampusSustainability(
      rainwaterWaterDemandPercent: parseNum(
        json['rainwater_water_demand_percent'],
      ),
      solarEnergyDemandPercent: parseNum(json['solar_energy_demand_percent']),
    );
  }
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
    required this.images,
    required this.highlights,
    required this.nearbyAreas,
    required this.profile,
    required this.facilities,
    required this.sustainability,
    required this.primaryEmail,
    required this.primaryPhone,
    required this.primaryPhoneRaw,
    required this.allEmails,
    required this.allPhones,
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
  final List<String> images;
  final List<String> highlights;
  final List<String> nearbyAreas;
  final CampusProfile? profile;
  final CampusFacilities? facilities;
  final CampusSustainability? sustainability;
  final String primaryEmail;
  final String primaryPhone;
  final String primaryPhoneRaw;
  final List<String> allEmails;
  final List<String> allPhones;
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

    final nearbyRaw = json['nearby_areas'];
    final nearbyAreas = nearbyRaw is List
        ? nearbyRaw
              .map((item) => '$item'.trim())
              .where((item) => item.isNotEmpty)
              .toList(growable: false)
        : const <String>[];

    final profileRaw = json['campus_profile'] ?? json['profile'];
    final profile = profileRaw is Map
        ? CampusProfile.fromJson(profileRaw)
        : null;

    final facilitiesRaw = json['learning_facilities'] ?? json['facilities'];
    final facilities = facilitiesRaw is Map
        ? CampusFacilities.fromJson(facilitiesRaw)
        : null;

    final sustainRaw = json['sustainability'];
    final sustainability = sustainRaw is Map
        ? CampusSustainability.fromJson(sustainRaw)
        : null;

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

    final rawAllEmails = contactMap?['emails'];
    final allEmails = rawAllEmails is List
        ? rawAllEmails
              .map((item) => '$item'.trim())
              .where((item) => item.isNotEmpty)
              .toSet()
              .toList(growable: false)
        : const <String>[];

    final rawAllPhones = contactMap?['phones'];
    final allPhones = rawAllPhones is List
        ? rawAllPhones
              .map((item) => '$item'.trim())
              .where((item) => item.isNotEmpty)
              .toList(growable: false)
        : const <String>[];

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

    final existingOfficeEmails = offices.expand((o) => o.emails).toSet();
    final emergencyEmails = emergencies
        .map((e) => e.email)
        .where((e) => e.isNotEmpty)
        .toSet();
    final unassignedEmails = allEmails
        .where(
          (e) =>
              !existingOfficeEmails.contains(e) && !emergencyEmails.contains(e),
        )
        .toList(growable: false);
    if (unassignedEmails.isNotEmpty) {
      offices.add(
        CampusOfficeContact(
          office: 'Other Inquiries',
          emails: unassignedEmails,
        ),
      );
    }

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
      transportScheduleUrl: '${json['schedule_url'] ?? ''}'.trim().isNotEmpty
          ? '${json['schedule_url'] ?? ''}'.trim()
          : '${transportMap?['schedule_url'] ?? ''}'.trim(),
      images: images,
      highlights: highlights,
      nearbyAreas: nearbyAreas,
      profile: profile,
      facilities: facilities,
      sustainability: sustainability,
      primaryEmail: primaryEmail,
      primaryPhone: primaryPhone,
      primaryPhoneRaw: primaryPhoneRaw,
      allEmails: allEmails,
      allPhones: allPhones,
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
                color: BracuPalette.card(sheetContext).withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: textSecondary.withValues(alpha: 0.16),
                ),
              ),
              child: child,
            );
          }

          Widget statChip({
            required IconData icon,
            required String label,
            required String value,
          }) {
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: BracuPalette.card(sheetContext).withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: textSecondary.withValues(alpha: 0.12),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 16, color: BracuPalette.primary),
                  const Gap(6),
                  Text(
                    '$label: ',
                    style: TextStyle(
                      color: textSecondary,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    value,
                    style: TextStyle(
                      color: textPrimary,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
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
              if (mapData.profile != null && mapData.profile!.hasData) ...[
                sectionTitle('Campus Profile'),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (mapData.profile!.landAreaAcres != null)
                      statChip(
                        icon: Icons.landscape_rounded,
                        label: 'Land Area',
                        value: '${mapData.profile!.landAreaAcres} Acres',
                      ),
                    if (mapData.profile!.buildingAreaSqft != null)
                      statChip(
                        icon: Icons.apartment_rounded,
                        label: 'Building Area',
                        value: '${mapData.profile!.buildingAreaSqft} sq ft',
                      ),
                    if (mapData.profile!.buildingFloors != null)
                      statChip(
                        icon: Icons.layers_rounded,
                        label: 'Floors',
                        value: '${mapData.profile!.buildingFloors} Stories',
                      ),
                    if (mapData.profile!.basements != null)
                      statChip(
                        icon: Icons.foundation_rounded,
                        label: 'Basements',
                        value: '${mapData.profile!.basements}',
                      ),
                    if (mapData.profile!.studentCapacityMin != null &&
                        mapData.profile!.studentCapacityMax != null)
                      statChip(
                        icon: Icons.groups_rounded,
                        label: 'Capacity',
                        value:
                            '${mapData.profile!.studentCapacityMin} - ${mapData.profile!.studentCapacityMax} Students',
                      ),
                  ],
                ),
              ],
              if (mapData.facilities != null &&
                  mapData.facilities!.hasData) ...[
                sectionTitle('Learning Facilities'),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (mapData.facilities!.classrooms != null)
                      statChip(
                        icon: Icons.school_rounded,
                        label: 'Classrooms',
                        value: '${mapData.facilities!.classrooms}',
                      ),
                    if (mapData.facilities!.lectureTheatres != null)
                      statChip(
                        icon: Icons.theater_comedy_rounded,
                        label: 'Lecture Theatres',
                        value: '${mapData.facilities!.lectureTheatres}',
                      ),
                    if (mapData.facilities!.laboratories != null)
                      statChip(
                        icon: Icons.science_rounded,
                        label: 'Laboratories',
                        value: '${mapData.facilities!.laboratories}',
                      ),
                    if (mapData.facilities!.libraryBooks != null)
                      statChip(
                        icon: Icons.menu_book_rounded,
                        label: 'Library Books',
                        value: '${mapData.facilities!.libraryBooks}+',
                      ),
                    if (mapData.facilities!.libraryHasArVr)
                      statChip(
                        icon: Icons.view_in_ar_rounded,
                        label: 'AR/VR',
                        value: 'Supported',
                      ),
                  ],
                ),
              ],
              if (mapData.sustainability != null &&
                  mapData.sustainability!.hasData) ...[
                sectionTitle('Sustainability'),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (mapData.sustainability!.rainwaterWaterDemandPercent !=
                        null)
                      statChip(
                        icon: Icons.water_drop_rounded,
                        label: 'Rainwater System',
                        value:
                            '${mapData.sustainability!.rainwaterWaterDemandPercent}% demand',
                      ),
                    if (mapData.sustainability!.solarEnergyDemandPercent !=
                        null)
                      statChip(
                        icon: Icons.solar_power_rounded,
                        label: 'Solar Energy',
                        value:
                            '${mapData.sustainability!.solarEnergyDemandPercent}% demand',
                      ),
                  ],
                ),
              ],
              if (mapData.nearbyAreas.isNotEmpty) ...[
                sectionTitle('Nearby Accessible Areas'),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: mapData.nearbyAreas
                      .map(
                        (area) => Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: BracuPalette.card(
                              sheetContext,
                            ).withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: textSecondary.withValues(alpha: 0.12),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.location_on_outlined,
                                size: 13,
                                color: BracuPalette.primary,
                              ),
                              const Gap(4),
                              Text(
                                area,
                                style: TextStyle(
                                  color: textPrimary,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                      .toList(growable: false),
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
