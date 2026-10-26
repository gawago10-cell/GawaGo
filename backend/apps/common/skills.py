"""The skill and service catalog every layer offers.

AGENTS.md V names two kinds of worker: domestic helpers (cleaning, cooking,
laundry, childcare, elder care and similar) and skilled workers (electrical,
plumbing, carpentry, painting, aircon repair, welding and similar). The
clients used to offer only House Cleaning, Laundry, Cooking and "Other", so a
tradesperson had to type their trade as free text, and the word "Other" was
saved as a skill of its own.

This list is the one catalog: the web and mobile skill pickers and the Post a
Job service types offer exactly these (apps/common/test_reference_data.py
fails if they drift), and the analytics group jobs by them. A worker or job
can still name a skill outside the catalog; it is typed in place of choosing
"Other", never stored as "Other".
"""

from apps.matching.services import normalize_skill_label

SKILL_CATALOG = [
    "House Cleaning",
    "Laundry",
    "Cooking",
    "Childcare",
    "Elder Care",
    "Gardening",
    "Driving",
    "Electrical Work",
    "Plumbing",
    "Carpentry",
    "Painting",
    "Aircon Repair",
    "Welding",
]

# The clients' "something else" choice. It stands for a skill the user types,
# so it is never a skill itself.
OTHER_SKILL_CHOICE = "Other"

_CATALOG_BY_KEY = {normalize_skill_label(name): name for name in SKILL_CATALOG}


def is_other_placeholder(value):
    return " ".join(str(value or "").split()).casefold() == OTHER_SKILL_CHOICE.casefold()


def canonical_skill_label(value):
    """The catalog name for a skill written any recognised way ("Electrician",
    "tubero", "Aircon Repair/Cleaning"), or the trimmed text when it is not in
    the catalog."""
    text = " ".join(str(value or "").split())
    return _CATALOG_BY_KEY.get(normalize_skill_label(text), text)
