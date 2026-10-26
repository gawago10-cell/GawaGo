import 'package:latlong2/latlong.dart';

/// Matches the backend's MAX_WORKER_SKILLS and AGENTS.md (at most 3).
const int maxWorkerSkills = 3;

/// Not a skill: picking it asks for a skill outside the catalog by name, and
/// the word itself is never saved.
const String gawagoOtherSkill = 'Other';

/// The skill catalog: domestic work first, then the skilled trades (AGENTS.md
/// V). Must match SKILL_CATALOG in backend/apps/common/skills.py (checked by
/// backend/apps/common/test_reference_data.py), plus [gawagoOtherSkill].
const List<String> gawagoSkills = [
  'House Cleaning',
  'Laundry',
  'Cooking',
  'Childcare',
  'Elder Care',
  'Gardening',
  'Driving',
  'Electrical Work',
  'Plumbing',
  'Carpentry',
  'Painting',
  'Aircon Repair',
  'Welding',
  gawagoOtherSkill,
];

/// All 66 barangays of Tayabas City. Must match backend/apps/common/barangays.py
/// (checked by backend/apps/common/test_reference_data.py).
const List<String> gawagoBarangays = [
  'Alitao',
  'Alsam Ibaba',
  'Alsam Ilaya',
  'Alupay',
  'Angeles Zone I',
  'Angeles Zone II',
  'Angeles Zone III',
  'Angeles Zone IV',
  'Angustias Zone I',
  'Angustias Zone II',
  'Angustias Zone III',
  'Angustias Zone IV',
  'Anos',
  'Ayaas',
  'Baguio',
  'Banilad',
  'Bukal Ibaba',
  'Bukal Ilaya',
  'Calantas',
  'Calumpang',
  'Camaysa',
  'Dapdap',
  'Domoit Kanluran',
  'Domoit Silangan',
  'Gibanga',
  'Ibas',
  'Ilasan Ibaba',
  'Ilasan Ilaya',
  'Ipilan',
  'Isabang',
  'Katigan Kanluran',
  'Katigan Silangan',
  'Lakawan',
  'Lalo',
  'Lawigue',
  'Lita',
  'Malaoa',
  'Masin',
  'Mate',
  'Mateuna',
  'Mayowe',
  'Nangka Ibaba',
  'Nangka Ilaya',
  'Opias',
  'Palale Ibaba',
  'Palale Ilaya',
  'Palale Kanluran',
  'Palale Silangan',
  'Pandakaki',
  'Pook',
  'Potol',
  'San Diego Zone I',
  'San Diego Zone II',
  'San Diego Zone III',
  'San Diego Zone IV',
  'San Isidro Zone I',
  'San Isidro Zone II',
  'San Isidro Zone III',
  'San Isidro Zone IV',
  'San Roque Zone I',
  'San Roque Zone II',
  'Talolong',
  'Tamlong',
  'Tongko',
  'Valencia',
  'Wakas',
];

/// Drawer label for the verification page, worded like the website's menu.
/// New profiles default to status "pending", so "Under Review" comes from an
/// actually submitted request ([requestStatus]), not the profile status.
String verificationNavLabel(String? status, String? requestStatus) {
  if (status == 'verified') return 'Verified';
  if (requestStatus == 'pending') return 'Under Review';
  if (status == 'rejected') return 'Verify Again';
  return 'Get Verified';
}

/// Mirrors VerificationRequest.ID_TYPE_CHOICES in apps/common/models.py. The
/// backend rejects anything outside this list, so the two must stay in step.
const gawagoGovernmentIdTypes = <({String value, String label})>[
  (value: 'national_id', label: 'National ID (PhilSys)'),
  (value: 'passport', label: 'Passport'),
  (value: 'drivers_license', label: "Driver's License"),
  (value: 'voter_id', label: 'Voter ID'),
  (value: 'tin', label: 'TIN ID'),
  (value: 'umid', label: 'UMID'),
  (value: 'postal_id', label: 'Postal ID'),
  (value: 'other', label: 'Other Government ID'),
];

String _cleanSkillName(String value) =>
    value.replaceAll(RegExp(r'\s+'), ' ').trim();

bool isOtherSkillChoice(String value) =>
    _cleanSkillName(value).toLowerCase() == gawagoOtherSkill.toLowerCase();

/// The skills a worker form saves: the ticked catalog skills, plus the typed
/// one when [gawagoOtherSkill] is ticked. "Other" itself is never saved -- it
/// used to be, taking one of the three slots and lowering every match score.
/// Names differing only in case or spacing count once.
List<String> resolveWorkerSkills(
  Iterable<String> selected,
  String customSkill,
) {
  final names = <String>[];
  final seen = <String>{};
  void add(String value) {
    final name = _cleanSkillName(value);
    final key = name.toLowerCase();
    if (name.isEmpty || isOtherSkillChoice(name) || !seen.add(key)) return;
    names.add(name);
  }

  final chosen = selected.toList();
  chosen.forEach(add);
  if (chosen.any(isOtherSkillChoice)) add(customSkill);
  return names;
}

/// Why a worker's skill choice can't be saved, or null when it can.
String? workerSkillsProblem(Iterable<String> selected, String customSkill) {
  final chosen = selected.toList();
  if (chosen.any(isOtherSkillChoice) &&
      (_cleanSkillName(customSkill).isEmpty ||
          isOtherSkillChoice(customSkill))) {
    return 'Type the name of your other skill, or untick Other.';
  }
  final skills = resolveWorkerSkills(chosen, customSkill);
  if (skills.isEmpty) return 'Choose at least one skill.';
  if (skills.length > maxWorkerSkills) {
    return 'You can list up to $maxWorkerSkills skills, including a typed one.';
  }
  return null;
}

/// Centre of each barangay, from backend/apps/common/barangays.py (checked
/// by backend/apps/common/test_reference_data.py). The maps move here when a
/// barangay is chosen, so a pin lands in that barangay rather than wherever
/// the map happened to be.
const Map<String, ({double latitude, double longitude})>
gawagoBarangayCenters = {
  'Alitao': (latitude: 14.053732435726491, longitude: 121.53367247279074),
  'Alsam Ibaba': (latitude: 14.0286, longitude: 121.6317),
  'Alsam Ilaya': (latitude: 14.0413, longitude: 121.6336),
  'Alupay': (latitude: 14.058062231209304, longitude: 121.60894317598026),
  'Angeles Zone I': (latitude: 14.028, longitude: 121.5942),
  'Angeles Zone II': (latitude: 14.0282, longitude: 121.5932),
  'Angeles Zone III': (latitude: 14.029, longitude: 121.5941),
  'Angeles Zone IV': (latitude: 14.03, longitude: 121.5955),
  'Angustias Zone I': (latitude: 14.0314, longitude: 121.5893),
  'Angustias Zone II': (latitude: 14.0326, longitude: 121.5904),
  'Angustias Zone III': (latitude: 14.0336, longitude: 121.5913),
  'Angustias Zone IV': (latitude: 14.0334, longitude: 121.5902),
  'Anos': (latitude: 13.99232619250926, longitude: 121.5687256763307),
  'Ayaas': (latitude: 14.033228404082344, longitude: 121.61280358513223),
  'Baguio': (latitude: 14.021320928095191, longitude: 121.58003973115441),
  'Banilad': (latitude: 14.04366598567965, longitude: 121.60287713844916),
  'Bukal Ibaba': (latitude: 14.0091, longitude: 121.5605),
  'Bukal Ilaya': (latitude: 14.027, longitude: 121.5357),
  'Calantas': (latitude: 14.0366, longitude: 121.5459),
  'Calumpang': (latitude: 13.976661577650393, longitude: 121.55620698162966),
  'Camaysa': (latitude: 14.061311651286287, longitude: 121.55211748652624),
  'Dapdap': (latitude: 14.059836954143305, longitude: 121.56928155311572),
  'Domoit Kanluran': (latitude: 13.9812, longitude: 121.5837),
  'Domoit Silangan': (latitude: 13.9784, longitude: 121.5936),
  'Gibanga': (latitude: 14.02426437684045, longitude: 121.52448299373229),
  'Ibas': (latitude: 14.056263954528147, longitude: 121.5858639459556),
  'Ilasan Ibaba': (latitude: 14.0658, longitude: 121.6327),
  'Ilasan Ilaya': (latitude: 14.076395444822706, longitude: 121.62660976250517),
  'Ipilan': (latitude: 14.033357570914804, longitude: 121.56833532099283),
  'Isabang': (latitude: 13.962274547948905, longitude: 121.56328409695064),
  'Katigan Kanluran': (
    latitude: 14.046025691828351,
    longitude: 121.6202812396619,
  ),
  'Katigan Silangan': (
    latitude: 14.060227861113688,
    longitude: 121.62154538337464,
  ),
  'Lakawan': (latitude: 14.009582881492914, longitude: 121.62560074991586),
  'Lalo': (latitude: 14.050261202405046, longitude: 121.55717481490423),
  'Lawigue': (latitude: 14.0308, longitude: 121.6575),
  'Lita': (latitude: 14.017699813459267, longitude: 121.59813443683436),
  'Malaoa': (latitude: 14.0142, longitude: 121.5758),
  'Masin': (latitude: 14.0557, longitude: 121.6404),
  'Mate': (latitude: 14.0068, longitude: 121.6401),
  'Mateuna': (latitude: 14.023782235513432, longitude: 121.6406),
  'Mayowe': (latitude: 13.97392868959356, longitude: 121.5783335732242),
  'Nangka Ibaba': (latitude: 13.9969, longitude: 121.6022),
  'Nangka Ilaya': (latitude: 14.0135, longitude: 121.597),
  'Opias': (latitude: 14.036073743242486, longitude: 121.59254781007984),
  'Palale Ibaba': (latitude: 14.061429877540817, longitude: 121.70714387691235),
  'Palale Ilaya': (latitude: 14.054262032583141, longitude: 121.6530714222272),
  'Palale Kanluran': (
    latitude: 14.041216405063171,
    longitude: 121.6540020663721,
  ),
  'Palale Silangan': (
    latitude: 14.089421743230861,
    longitude: 121.68915654043055,
  ),
  'Pandakaki': (latitude: 13.9925, longitude: 121.6265),
  'Pook': (latitude: 14.0522, longitude: 121.5957),
  'Potol': (latitude: 13.9951, longitude: 121.5869),
  'San Diego Zone I': (latitude: 14.029, longitude: 121.5922),
  'San Diego Zone II': (latitude: 14.0302, longitude: 121.5932),
  'San Diego Zone III': (latitude: 14.031, longitude: 121.594),
  'San Diego Zone IV': (latitude: 14.0317, longitude: 121.5946),
  'San Isidro Zone I': (latitude: 14.0279, longitude: 121.5882),
  'San Isidro Zone II': (latitude: 14.0287, longitude: 121.5874),
  'San Isidro Zone III': (latitude: 14.0289, longitude: 121.5888),
  'San Isidro Zone IV': (latitude: 14.0298, longitude: 121.5882),
  'San Roque Zone I': (latitude: 14.0306, longitude: 121.591),
  'San Roque Zone II': (latitude: 14.0324, longitude: 121.5926),
  'Talolong': (latitude: 14.077712524215334, longitude: 121.61401135611793),
  'Tamlong': (latitude: 14.069116148209835, longitude: 121.60191813524901),
  'Tongko': (latitude: 13.987459902846487, longitude: 121.60973707319776),
  'Valencia': (latitude: 14.0807, longitude: 121.6436),
  'Wakas': (latitude: 14.006911431929879, longitude: 121.60872288744254),
};

/// The centre of [barangay] as a map point, or null when none is chosen.
LatLng? barangayCenter(String? barangay) {
  final center = barangay == null ? null : gawagoBarangayCenters[barangay];
  return center == null ? null : LatLng(center.latitude, center.longitude);
}
