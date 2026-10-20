"""The service area's barangays, and the one parser that reads a barangay out
of a free-text location label.

Both the dashboard and the date-bounded reports group jobs by barangay, and
they used to do it differently: the dashboard looked for a known barangay
anywhere in the label while reports took whatever sat before the first comma.
A label like "Purok 3, Lalo, Tayabas City, Quezon" therefore counted towards
Lalo on one screen and created a bogus "Purok 3" row on the other. The job
serializer also masks a label down to its barangay for workers who have not
been hired, which needs the same reading.
"""

BARANGAY_CENTERS = {
    "Alitao": {"latitude": 14.053732435726491, "longitude": 121.53367247279074},
    "Alupay": {"latitude": 14.058062231209304, "longitude": 121.60894317598026},
    "Anos": {"latitude": 13.99232619250926, "longitude": 121.5687256763307},
    "Ayaas": {"latitude": 14.033228404082344, "longitude": 121.61280358513223},
    "Baguio": {"latitude": 14.021320928095191, "longitude": 121.58003973115441},
    "Banilad": {"latitude": 14.04366598567965, "longitude": 121.60287713844916},
    "Calumpang": {"latitude": 13.976661577650393, "longitude": 121.55620698162966},
    "Camaysa": {"latitude": 14.061311651286287, "longitude": 121.55211748652624},
    "Dapdap": {"latitude": 14.059836954143305, "longitude": 121.56928155311572},
    "Gibanga": {"latitude": 14.02426437684045, "longitude": 121.52448299373229},
    "Ibas": {"latitude": 14.056263954528147, "longitude": 121.5858639459556},
    "Ilasan Ilaya": {"latitude": 14.076395444822706, "longitude": 121.62660976250517},
    "Ilasan Ibaba": {"latitude": 14.076395444822706, "longitude": 121.62660976250517},
    "Isabang": {"latitude": 13.962274547948905, "longitude": 121.56328409695064},
    "Ipilan": {"latitude": 14.033357570914804, "longitude": 121.56833532099283},
    "Katigan Kanluran": {"latitude": 14.046025691828351, "longitude": 121.6202812396619},
    "Katigan Silangan": {"latitude": 14.060227861113688, "longitude": 121.62154538337464},
    "Lalo": {"latitude": 14.050261202405046, "longitude": 121.55717481490423},
    "Lakawan": {"latitude": 14.009582881492914, "longitude": 121.62560074991586},
    "Lita": {"latitude": 14.017699813459267, "longitude": 121.59813443683436},
    "Mateuna": {"latitude": 14.023782235513432, "longitude": 121.6406},
    "Mayowe": {"latitude": 13.97392868959356, "longitude": 121.5783335732242},
    "Opias": {"latitude": 14.036073743242486, "longitude": 121.59254781007984},
    "Palale Ilaya": {"latitude": 14.054262032583141, "longitude": 121.6530714222272},
    "Palale Kanluran": {"latitude": 14.041216405063171, "longitude": 121.6540020663721},
    "Palale Ibaba": {"latitude": 14.061429877540817, "longitude": 121.70714387691235},
    "Palale Silangan": {"latitude": 14.089421743230861, "longitude": 121.68915654043055},
    "Tamlong": {"latitude": 14.069116148209835, "longitude": 121.60191813524901},
    "Talolong": {"latitude": 14.077712524215334, "longitude": 121.61401135611793},
    "Tongko": {"latitude": 13.987459902846487, "longitude": 121.60973707319776},
    "Wakas": {"latitude": 14.006911431929879, "longitude": 121.60872288744254},
}

BARANGAYS = list(BARANGAY_CENTERS.keys())

CITY = "Tayabas City"
PROVINCE = "Quezon"


def normalize_barangay_name(value):
    normalized = str(value or "").strip()
    if normalized.lower().startswith("barangay "):
        normalized = normalized[9:].strip()
    if normalized.lower().startswith("brgy."):
        normalized = normalized[5:].strip()
    elif normalized.lower().startswith("brgy"):
        normalized = normalized[4:].strip()
    for barangay in BARANGAYS:
        if barangay.lower() == normalized.lower():
            return barangay
    return normalized


def barangay_from_location_label(value):
    """The barangay named anywhere in a label, however the label was built.

    The two clients compose labels in opposite orders ("barangay, street" on
    web, "street, barangay, Tayabas City, Quezon" on mobile), so position
    cannot be relied on. Falls back to the first segment when no known
    barangay appears.
    """
    parts = [part.strip() for part in str(value or "").split(",") if part.strip()]
    for part in parts:
        normalized = normalize_barangay_name(part)
        if normalized in BARANGAYS:
            return normalized
    return normalize_barangay_name(parts[0]) if parts else ""
