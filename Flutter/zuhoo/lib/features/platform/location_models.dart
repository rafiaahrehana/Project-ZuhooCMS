/// A node in a country's administrative hierarchy — Division/District/Upazila/
/// Police Station for Bangladesh, State/County/City/Precinct for the US, and so
/// on. `type` is `COUNTRY` for a country row (only ever read, never written —
/// there is no create/update/delete for those) or `LEVEL1`..`LEVEL4` for a node
/// underneath one.
///
/// [code] is the ISO country code ("BD", "US") and only ever set on a
/// `COUNTRY` row — [Location] itself carries no code column, so it is always
/// null below that.
class GeoNode {
  const GeoNode({
    required this.id,
    required this.name,
    required this.type,
    this.code,
  });

  final int id;
  final String name;
  final String type;
  final String? code;

  bool get isCountry => type == 'COUNTRY';

  factory GeoNode.fromJson(Map<String, dynamic> json) => GeoNode(
        id: (json['id'] as num?)?.toInt() ?? 0,
        name: json['name'] as String? ?? '',
        type: json['type'] as String? ?? '',
        code: json['code'] as String?,
      );
}

/// POST /locations
///
/// A LEVEL1 node needs [countryId] (the country it belongs to); LEVEL2-4 need
/// [parentId] (the node one level up) instead — never both. Angular's own
/// Locations screen gets this backwards for LEVEL1 (always sends `parentId`,
/// never `countryId`), which the backend rejects outright; this does not
/// repeat that.
class LocationCreateRequest {
  const LocationCreateRequest({
    required this.name,
    required this.type,
    this.countryId,
    this.parentId,
  });

  final String name;

  /// `LEVEL1`..`LEVEL4`.
  final String type;
  final int? countryId;
  final int? parentId;

  Map<String, dynamic> toJson() => {
        'name': name.trim(),
        'type': type,
        if (countryId != null) 'countryId': countryId,
        if (parentId != null) 'parentId': parentId,
      };
}

/// PUT /locations/{id}. Rename only — the backend also accepts a `parentId`
/// to re-parent a node, but nothing here offers that.
class LocationUpdateRequest {
  const LocationUpdateRequest({required this.name});

  final String name;

  Map<String, dynamic> toJson() => {'name': name.trim()};
}

/// What each level is actually called, country by country — a "District" in
/// Bangladesh is a "County" in the US and a "Province" in Canada. Ported from
/// the web app's `globalHierarchyLabels` so the same countries read the same
/// way here. A code missing from this table (any not seeded on the backend)
/// falls back to a plain "Level N".
const Map<String, List<String>> _hierarchyLabels = {
  'BD': ['Division', 'District', 'Upazila / Municipality', 'Police Station'],
  'IN': ['State / Union Territory', 'District', 'Sub-district / Tehsil', 'Police Station'],
  'PK': ['Province / Territory', 'District', 'Tehsil / Town', 'Police Station'],
  'LK': ['Province', 'District', 'Divisional Secretariat', 'Police Station'],
  'NP': ['Province', 'District', 'Municipality', 'Ward / Station'],
  'MV': ['Atoll', 'Island', 'City / Ward', 'Police Station'],
  'AF': ['Province (Wilayat)', 'District (Wuleswali)', 'City / Municipality', 'Police District'],
  'CN': ['Province', 'Prefecture', 'County / District', 'Township / Police Station'],
  'JP': ['Prefecture', 'Subprefecture', 'City / Ward', 'Police Box (Koban)'],
  'KR': ['Province', 'City / County', 'District (Gu)', 'Neighborhood (Dong)'],
  'ID': ['Province', 'Regency / City', 'District (Kecamatan)', 'Village / Police Sector'],
  'MY': ['State', 'District', 'Mukim (Commune)', 'Police Station'],
  'PH': ['Region', 'Province', 'City / Municipality', 'Barangay / Precinct'],
  'SG': ['Region', 'Planning Area', 'Subzone', 'Police Division'],
  'TH': ['Province', 'District (Amphoe)', 'Sub-district (Tambon)', 'Village / Station'],
  'VN': ['Province', 'District', 'Commune / Ward', 'Police Post'],
  'TW': ['Special Municipality / County', 'District / City', 'Village', 'Neighborhood'],
  'MM': ['State / Region', 'District', 'Township', 'Ward / Village'],
  'KH': ['Province', 'District', 'Commune', 'Village'],
  'US': ['State', 'County', 'City / Township', 'Police Precinct / Station'],
  'CA': ['Province / Territory', 'Regional Municipality', 'City / Town', 'Police Division'],
  'MX': ['State', 'Municipality', 'City', 'Neighborhood (Colonia)'],
  'BR': ['State', 'Mesoregion', 'Microregion', 'Municipality / District'],
  'AR': ['Province', 'Department', 'Municipality', 'Police Station'],
  'CO': ['Department', 'Province', 'Municipality', 'Comuna / Corregimiento'],
  'CL': ['Region', 'Province', 'Commune', 'Police Unit (Comisaría)'],
  'PE': ['Region', 'Province', 'District', 'Police Station'],
  'VE': ['State', 'Municipality', 'Parish', 'Police Sector'],
  'EC': ['Province', 'Canton', 'Parish', 'Neighborhood'],
  'CU': ['Province', 'Municipality', 'Ward', 'Police Station'],
  'BO': ['Department', 'Province', 'Municipality', 'Canton'],
  'PY': ['Department', 'District', 'Municipality', 'Neighborhood'],
  'UY': ['Department', 'Municipality', 'City / Town', 'Police Precinct'],
  'CR': ['Province', 'Canton', 'District', 'Neighborhood'],
  'PA': ['Province', 'District', 'Corregimiento', 'Police Zone'],
  'SV': ['Department', 'District', 'Municipality', 'Police Post'],
  'GT': ['Department', 'Municipality', 'Village', 'Police Station'],
  'HN': ['Department', 'Municipality', 'Village / Hamlet', 'Police Unit'],
  'DO': ['Province', 'Municipality', 'Municipal District', 'Section / Barrio'],
  'GB': ['Country (e.g., England)', 'County', 'City / Town', 'Police Constabulary'],
  'DE': ['State (Bundesland)', 'District (Kreis)', 'Municipality', 'Police Station'],
  'FR': ['Region', 'Department', 'Arrondissement', 'Commune / Police Station'],
  'IT': ['Region', 'Province', 'Municipality', 'Questura / Station'],
  'ES': ['Autonomous Community', 'Province', 'Comarca', 'Municipality'],
  'RU': ['Republic / Oblast', 'District (Raion)', 'City / Town', 'Police Department'],
  'UA': ['Oblast', 'Raion', 'City / Hromada', 'Police Station'],
  'PL': ['Voivodeship', 'County (Powiat)', 'Commune (Gmina)', 'Police Precinct'],
  'NL': ['Province', 'COROP Region', 'Municipality', 'Police Unit'],
  'BE': ['Region', 'Province', 'Arrondissement', 'Municipality / Police Zone'],
  'SE': ['County', 'Municipality', 'City / Town', 'Police District'],
  'CH': ['Canton', 'District', 'Municipality', 'Police Post'],
  'AT': ['State', 'District', 'Municipality', 'Police Inspectorate'],
  'PT': ['District', 'Municipality', 'Parish (Freguesia)', 'Police Station'],
  'GR': ['Region', 'Regional Unit', 'Municipality', 'Police Department'],
  'CZ': ['Region', 'District', 'Municipality', 'Police Station'],
  'RO': ['County', 'City / Town', 'Commune', 'Police Section'],
  'HU': ['County', 'District', 'Municipality', 'Police Captaincy'],
  'IE': ['Province', 'County', 'City / Town', 'Garda Station'],
  'DK': ['Region', 'Municipality', 'City', 'Police District'],
  'FI': ['Region', 'Sub-region', 'Municipality', 'Police Department'],
  'NO': ['County', 'Municipality', 'City', 'Police District'],
  'TR': ['Province (İl)', 'District (İlçe)', 'Municipality', 'Neighborhood (Mahalle)'],
  'BY': ['Oblast', 'Raion', 'City / Town', 'Police Station'],
  'RS': ['District', 'Municipality', 'City / Village', 'Police Station'],
  'BG': ['Province', 'Municipality', 'City / Village', 'Police Station'],
  'SK': ['Region', 'District', 'Municipality', 'Police Station'],
  'HR': ['County', 'City / Town', 'Municipality', 'Police Station'],
  'LT': ['County', 'Municipality', 'Eldership', 'Police Commissariat'],
  'LV': ['Region', 'Municipality', 'City / Parish', 'Police Station'],
  'AE': ['Emirate', 'Region', 'City / Area', 'Police Station'],
  'SA': ['Province', 'Governorate', 'Sub-Governorate', 'Police Center'],
  'EG': ['Governorate', 'Markaz (Region)', 'City', 'District / Station'],
  'IR': ['Province (Ostan)', 'County (Shahrestan)', 'District (Bakhsh)', 'City / Rural District'],
  'IL': ['District', 'Sub-district', 'City / Local Council', 'Police Station'],
  'IQ': ['Governorate', 'District', 'Sub-district', 'Police Station'],
  'DZ': ['Province (Wilaya)', 'District (Daïra)', 'Commune', 'Police Station'],
  'MA': ['Region', 'Prefecture / Province', 'Arrondissement / Commune', 'Police District'],
  'QA': ['Municipality', 'Zone', 'District', 'Police Department'],
  'KW': ['Governorate', 'Area', 'Block', 'Police Station'],
  'OM': ['Governorate', 'Wilayat', 'City / Village', 'Police Station'],
  'LB': ['Governorate', 'District', 'Municipality', 'Police Station'],
  'JO': ['Governorate', 'District', 'Sub-district', 'Police Station'],
  'TN': ['Governorate', 'Delegation', 'Sector (Imada)', 'Police Station'],
  'ZA': ['Province', 'District Municipality', 'Local Municipality', 'Police Ward'],
  'NG': ['State', 'Local Government Area (LGA)', 'Ward', 'Police Command'],
  'KE': ['County', 'Sub-county', 'Ward', 'Police Division / Station'],
  'ET': ['Regional State', 'Zone', 'Woreda (District)', 'Kebele (Ward)'],
  'GH': ['Region', 'District', 'Metropolis / Municipality', 'Police Station'],
  'TZ': ['Region', 'District', 'Ward', 'Village / Police Station'],
  'UG': ['Region', 'District', 'County / Sub-county', 'Parish / Police Post'],
  'CI': ['District', 'Region', 'Department', 'Sub-prefecture / Commune'],
  'CM': ['Region', 'Division', 'Sub-division', 'Police District'],
  'AO': ['Province', 'Municipality', 'Commune', 'Police Station'],
  'ZM': ['Province', 'District', 'Constituency', 'Ward / Police Camp'],
  'ZW': ['Province', 'District', 'Ward', 'Police Station'],
  'SN': ['Region', 'Department', 'Arrondissement', 'Commune'],
  'RW': ['Province', 'District', 'Sector', 'Cell / Village'],
  'AU': ['State / Territory', 'Local Gov. Area (LGA)', 'Suburb / Town', 'Police District / Station'],
  'NZ': ['Region', 'Territorial Authority', 'Suburb', 'Police Station'],
  'FJ': ['Division', 'Province', 'District', 'Police Station'],
};

/// Human label for [level] (1-4) under [countryCode]. Falls back to "Level N"
/// for a country not in the table above, or no country context at all.
String hierarchyLabel(String? countryCode, int level) {
  final labels = _hierarchyLabels[countryCode];
  if (labels != null && level >= 1 && level <= labels.length) {
    return labels[level - 1];
  }
  return 'Level $level';
}

const _levelTypes = ['LEVEL1', 'LEVEL2', 'LEVEL3', 'LEVEL4'];

/// The `LocationType` a node one level deeper than [depth] (0 = country) is.
String locationTypeForDepth(int depth) => _levelTypes[depth.clamp(0, 3)];
