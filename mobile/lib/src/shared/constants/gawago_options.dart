/// Matches the backend's MAX_WORKER_SKILLS and AGENTS.md (at most 3).
const int maxWorkerSkills = 3;

const List<String> gawagoSkills = [
  'House Cleaning',
  'Laundry',
  'Cooking',
  'Other',
];

const List<String> gawagoBarangays = [
  'Alitao',
  'Alupay',
  'Anos',
  'Ayaas',
  'Baguio',
  'Banilad',
  'Calumpang',
  'Camaysa',
  'Dapdap',
  'Gibanga',
  'Ibas',
  'Ilasan Ilaya',
  'Ilasan Ibaba',
  'Isabang',
  'Ipilan',
  'Katigan Kanluran',
  'Katigan Silangan',
  'Lalo',
  'Lakawan',
  'Lita',
  'Mateuna',
  'Mayowe',
  'Opias',
  'Palale Ilaya',
  'Palale Kanluran',
  'Palale Ibaba',
  'Palale Silangan',
  'Tamlong',
  'Talolong',
  'Tongko',
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
