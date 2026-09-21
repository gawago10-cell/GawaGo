import { getApiBaseUrl } from "../api/apiClient";

export const MAX_WORKER_SKILLS = 3;
export const SKILLS = [
  "House Cleaning",
  "Laundry",
  "Cooking",
  "Other",
];
export const BARANGAYS = [
  "Alitao",
  "Alupay",
  "Anos",
  "Ayaas",
  "Baguio",
  "Banilad",
  "Calumpang",
  "Camaysa",
  "Dapdap",
  "Gibanga",
  "Ibas",
  "Ilasan Ilaya",
  "Ilasan Ibaba",
  "Isabang",
  "Ipilan",
  "Katigan Kanluran",
  "Katigan Silangan",
  "Lalo",
  "Lakawan",
  "Lita",
  "Mateuna",
  "Mayowe",
  "Opias",
  "Palale Ilaya",
  "Palale Kanluran",
  "Palale Ibaba",
  "Palale Silangan",
  "Tamlong",
  "Talolong",
  "Tongko",
  "Wakas",
];
export const STORAGE_KEYS = {
  workers: "gawago-registered-workers",
  households: "gawago-registered-households",
  jobs: "gawago-posted-jobs",
  chatMessages: "gawago-chat-messages",
  verificationRequests: "gawago-verification-requests",
  notificationReads: "gawago-notification-reads",
};
export const DEMO_DATA_VERSION = "v18";
export const DEMO_VERSION_KEY = "gawago-demo-data-version";
export const IS_DEMO_MODE = import.meta.env.VITE_DEMO_MODE === "true";
export const API_BASE_URL = getApiBaseUrl();
export const ACCOUNTS_API_BASE_URL = `${API_BASE_URL}/accounts`;
export const EMPTY_WORKER_FORM = {
  firstName: "",
  lastName: "",
  username: "",
  email: "",
  phone: "",
  barangay: "",
  streetAddress: "",
  latitude: null,
  longitude: null,
  locationLabel: "",
  locationSource: "",
  locationWarning: "",
  locationAccuracy: "",
  bio: "",
  hourlyRate: "0.00",
  dailyRate: "0.00",
  yearsExperience: "0",
  password: "",
  confirmPassword: "",
  skills: [],
  customSkill: "",
};
export const EMPTY_HOUSEHOLD_FORM = {
  firstName: "",
  lastName: "",
  username: "",
  email: "",
  phone: "",
  barangay: "",
  streetAddress: "",
  password: "",
  confirmPassword: "",
};
export const EMPTY_HOUSEHOLD_REVIEW_FORM = {
  rating: "5",
  feedback: "",
  jobId: "",
  quality_of_work: "",
  punctuality: "",
  communication: "",
  professionalism: "",
};
export const EMPTY_WORKER_FEEDBACK_FORM = {
  rating: "5",
  feedback: "",
  jobId: "",
  quality_of_work: "",
  punctuality: "",
  communication: "",
  professionalism: "",
};
export const GMAIL_ADDRESS_PATTERN = /^[A-Z0-9._%+-]+@gmail\.com$/i;
export const OPENROUTESERVICE_API_KEY = import.meta.env.VITE_OPENROUTESERVICE_API_KEY || "";
export const OPENROUTESERVICE_SEARCH_URL =
  import.meta.env.VITE_OPENROUTESERVICE_SEARCH_URL || "https://api.openrouteservice.org/geocode/search";
export const OPENROUTESERVICE_REVERSE_URL =
  import.meta.env.VITE_OPENROUTESERVICE_REVERSE_URL || "https://api.openrouteservice.org/geocode/reverse";
export const OPENROUTESERVICE_DIRECTIONS_URL =
  import.meta.env.VITE_OPENROUTESERVICE_DIRECTIONS_URL ||
  "https://api.openrouteservice.org/v2/directions/driving-car/geojson";
export const PHILIPPINES_MAP_CENTER = { latitude: 12.8797, longitude: 121.774 };
export const PHILIPPINES_MAP_BOUNDS = {
  south: 4.5,
  west: 116.87,
  north: 21.3,
  east: 126.65,
};
export const TAYABAS_CITY_CENTER = { latitude: 13.956, longitude: 121.592 };
export const TAYABAS_MAP_BOUNDS = {
  south: 13.9,
  west: 121.5,
  north: 14.11,
  east: 121.73,
};
// Validated categorical palette (dataviz skill reference palette, light mode):
// fixed hue order chosen so adjacent slots clear CVD-safety checks. Never reorder
// or cycle the first N slots independently -- add categories in this order.
// Mirrors SKILL_WEIGHT in backend/apps/matching/recommendations.py. Used only
// to describe the blend in the UI; the scores themselves come from the backend.
export const AI_SKILL_WEIGHT = 0.7;

export const ANALYTICS_CHART_COLORS = [
  "#2a78d6", // blue
  "#eb6834", // orange
  "#1baf7a", // aqua
  "#eda100", // yellow
  "#e87ba4", // magenta
  "#008300", // green
  "#4a3aa7", // violet
  "#e34948", // red
];
export const ANALYTICS_SERVICE_CATEGORIES = SKILLS.filter((skill) => skill !== "Other");
export const SHARED_DEMO_PASSWORD = "GawaGo123";
export const DEMO_LOCATIONS = [
  ["Alitao", 14.053732435726491, 121.53367247279074],
  ["Alupay", 14.058062231209304, 121.60894317598026],
  ["Anos", 13.99232619250926, 121.5687256763307],
  ["Ayaas", 14.033228404082344, 121.61280358513223],
  ["Baguio", 14.021320928095191, 121.58003973115441],
  ["Banilad", 14.04366598567965, 121.60287713844916],
  ["Calumpang", 13.976661577650393, 121.55620698162966],
  ["Camaysa", 14.061311651286287, 121.55211748652624],
  ["Dapdap", 14.059836954143305, 121.56928155311572],
  ["Gibanga", 14.02426437684045, 121.52448299373229],
  ["Ibas", 14.056263954528147, 121.5858639459556],
  ["Ilasan Ilaya", 14.076395444822706, 121.62660976250517],
  ["Ilasan Ibaba", 14.076395444822706, 121.62660976250517],
  ["Isabang", 13.962274547948905, 121.56328409695064],
  ["Ipilan", 14.033357570914804, 121.56833532099283],
  ["Katigan Kanluran", 14.046025691828351, 121.6202812396619],
  ["Katigan Silangan", 14.060227861113688, 121.62154538337464],
  ["Lalo", 14.050261202405046, 121.55717481490423],
  ["Lakawan", 14.009582881492914, 121.62560074991586],
  ["Lita", 14.017699813459267, 121.59813443683436],
  ["Mateuna", 14.023782235513432, 121.6406],
  ["Mayowe", 13.97392868959356, 121.5783335732242],
  ["Opias", 14.036073743242486, 121.59254781007984],
  ["Palale Ilaya", 14.054262032583141, 121.6530714222272],
  ["Palale Kanluran", 14.041216405063171, 121.6540020663721],
  ["Palale Ibaba", 14.061429877540817, 121.70714387691235],
  ["Palale Silangan", 14.089421743230861, 121.68915654043055],
  ["Tamlong", 14.069116148209835, 121.60191813524901],
  ["Talolong", 14.077712524215334, 121.61401135611793],
  ["Tongko", 13.987459902846487, 121.60973707319776],
  ["Wakas", 14.006911431929879, 121.60872288744254],
];
export const NUMBER_WORDS = ["One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine", "Ten"];
export const DEMO_HOUSEHOLD_ACCOUNTS = DEMO_LOCATIONS.map(([barangay, latitude, longitude], index) => ({
  id: `demo-household-${index + 1}`,
  username: `Household ${index + 1}`,
  password: SHARED_DEMO_PASSWORD,
  firstName: "Household",
  lastName: NUMBER_WORDS[index] || String(index + 1),
  email: `household${index + 1}@gmail.com`,
  phone: `91700000${String(index + 1).padStart(2, "0")}`,
  barangay,
  streetAddress: `Demo Street ${index + 1}`,
  latitude,
  longitude,
}));
export const DEMO_WORKER_TEMPLATES = [
  {
    skills: ["House Cleaning", "Laundry"],
    hourlyRate: "120.00",
    dailyRate: "650.00",
    yearsExperience: "3",
    verification: "Verified",
    rating: "4.90",
    reviewsDone: 3,
  },
  {
    skills: ["Plumbing", "Carpentry"],
    hourlyRate: "180.00",
    dailyRate: "900.00",
    yearsExperience: "5",
    verification: "Verified",
    rating: "4.50",
    reviewsDone: 2,
  },
  {
    skills: ["Electrical Work", "Aircon Repair/Cleaning"],
    hourlyRate: "200.00",
    dailyRate: "1000.00",
    yearsExperience: "4",
    verification: "Under Review",
    rating: "4.00",
    reviewsDone: 1,
  },
  {
    skills: ["Childcare", "Cooking"],
    hourlyRate: "130.00",
    dailyRate: "700.00",
    yearsExperience: "2",
    verification: "Rejected",
    rating: "3.00",
    reviewsDone: 1,
  },
  {
    skills: ["Laundry", "House Cleaning", "Cooking"],
    hourlyRate: "110.00",
    dailyRate: "600.00",
    yearsExperience: "1",
    verification: "Not Yet Verified",
    rating: "No ratings yet",
    reviewsDone: 0,
  },
  {
    skills: ["Gardening", "House Cleaning"],
    hourlyRate: "115.00",
    dailyRate: "620.00",
    yearsExperience: "2",
    verification: "Verified",
    rating: "4.70",
    reviewsDone: 2,
  },
  {
    skills: ["Painting", "Carpentry"],
    hourlyRate: "170.00",
    dailyRate: "850.00",
    yearsExperience: "6",
    verification: "Verified",
    rating: "4.80",
    reviewsDone: 4,
  },
  {
    skills: ["Elder Care", "Cooking"],
    hourlyRate: "150.00",
    dailyRate: "780.00",
    yearsExperience: "4",
    verification: "Under Review",
    rating: "4.20",
    reviewsDone: 1,
  },
  {
    skills: ["Welding", "Electrical Work"],
    hourlyRate: "220.00",
    dailyRate: "1200.00",
    yearsExperience: "7",
    verification: "Verified",
    rating: "4.60",
    reviewsDone: 3,
  },
  {
    skills: ["Driving", "Other"],
    hourlyRate: "160.00",
    dailyRate: "800.00",
    yearsExperience: "3",
    verification: "Not Yet Verified",
    rating: "No ratings yet",
    reviewsDone: 0,
  },
];
export const DEMO_WORKER_ACCOUNTS = DEMO_LOCATIONS.map(([barangay, latitude, longitude], index) => {
  const template = DEMO_WORKER_TEMPLATES[index % DEMO_WORKER_TEMPLATES.length];
  return {
    id: `demo-worker-${index + 1}`,
    username: `Worker${index + 1}`,
    password: SHARED_DEMO_PASSWORD,
    firstName: "Worker",
    lastName: NUMBER_WORDS[index] || String(index + 1),
    email: `worker${index + 1}@gmail.com`,
    phone: `91800000${String(index + 1).padStart(2, "0")}`,
    barangay,
    streetAddress: `Worker Street ${index + 1}`,
    bio: `Demo profile for Worker ${NUMBER_WORDS[index] || index + 1}.`,
    ...template,
    status: "Available",
    distanceKm: "0.00",
    latitude,
    longitude,
    avatar: "W",
    receivedReviews:
      template.reviewsDone > 0
        ? [
            {
              id: `demo-review-${index + 1}`,
              rating: Number.parseFloat(template.rating),
              feedback: "Demo review for analytics.",
              createdAt: "Recently",
            },
          ]
        : [],
    givenFeedback: [],
    verificationNotifications: [],
    applicationNotifications: [],
  };
});
export const DEMO_VERIFICATION_REQUESTS = [
  {
    id: "demo-verification-3",
    workerId: "demo-worker-3",
    workerUsername: "Worker3",
    workerName: "Worker Three",
    submittedAt: "Recently",
    reviewedAt: "",
    reviewedBy: "",
    status: "Pending",
    primaryIdName: "UMID",
    secondaryDocName: "Barangay Clearance",
    notes: "Awaiting admin review.",
  },
  {
    id: "demo-verification-4",
    workerId: "demo-worker-4",
    workerUsername: "Worker4",
    workerName: "Worker Four",
    submittedAt: "Recently",
    reviewedAt: "Recently",
    reviewedBy: "Super Admin",
    status: "Rejected",
    primaryIdName: "Driver License",
    secondaryDocName: "NBI Clearance",
    notes: "Document image needs resubmission.",
    reviewNote: "Please upload clearer documents.",
  },
];
export const DEMO_ACCOUNT_PASSWORDS = Object.fromEntries(
  [...DEMO_HOUSEHOLD_ACCOUNTS, ...DEMO_WORKER_ACCOUNTS].map((account) => [account.username, account.password]),
);
export const BARANGAY_CENTERS = {
  Alitao: { latitude: 14.053732435726491, longitude: 121.53367247279074 },
  Alupay: { latitude: 14.058062231209304, longitude: 121.60894317598026 },
  Anos: { latitude: 13.99232619250926, longitude: 121.5687256763307 },
  Ayaas: { latitude: 14.033228404082344, longitude: 121.61280358513223 },
  Baguio: { latitude: 14.021320928095191, longitude: 121.58003973115441 },
  Banilad: { latitude: 14.04366598567965, longitude: 121.60287713844916 },
  Calumpang: { latitude: 13.976661577650393, longitude: 121.55620698162966 },
  Camaysa: { latitude: 14.061311651286287, longitude: 121.55211748652624 },
  Dapdap: { latitude: 14.059836954143305, longitude: 121.56928155311572 },
  Gibanga: { latitude: 14.02426437684045, longitude: 121.52448299373229 },
  Ibas: { latitude: 14.056263954528147, longitude: 121.5858639459556 },
  "Ilasan Ilaya": { latitude: 14.076395444822706, longitude: 121.62660976250517 },
  "Ilasan Ibaba": { latitude: 14.076395444822706, longitude: 121.62660976250517 },
  Isabang: { latitude: 13.962274547948905, longitude: 121.56328409695064 },
  Ipilan: { latitude: 14.033357570914804, longitude: 121.56833532099283 },
  "Katigan Kanluran": { latitude: 14.046025691828351, longitude: 121.6202812396619 },
  "Katigan Silangan": { latitude: 14.060227861113688, longitude: 121.62154538337464 },
  Lalo: { latitude: 14.050261202405046, longitude: 121.55717481490423 },
  Lakawan: { latitude: 14.009582881492914, longitude: 121.62560074991586 },
  Lita: { latitude: 14.017699813459267, longitude: 121.59813443683436 },
  Mateuna: { latitude: 14.023782235513432, longitude: 121.6406 },
  Mayowe: { latitude: 13.97392868959356, longitude: 121.5783335732242 },
  Opias: { latitude: 14.036073743242486, longitude: 121.59254781007984 },
  "Palale Ilaya": { latitude: 14.054262032583141, longitude: 121.6530714222272 },
  "Palale Kanluran": { latitude: 14.041216405063171, longitude: 121.6540020663721 },
  "Palale Ibaba": { latitude: 14.061429877540817, longitude: 121.70714387691235 },
  "Palale Silangan": { latitude: 14.089421743230861, longitude: 121.68915654043055 },
  Tamlong: { latitude: 14.069116148209835, longitude: 121.60191813524901 },
  Talolong: { latitude: 14.077712524215334, longitude: 121.61401135611793 },
  Tongko: { latitude: 13.987459902846487, longitude: 121.60973707319776 },
  Wakas: { latitude: 14.006911431929879, longitude: 121.60872288744254 },
};
export const STATUS_PRIORITY = { Pending: 1, "Under Review": 2, Approved: 3, Rejected: 4 };
