"""What each side of a job may learn about the other, and when.

Locations are shared between signed-in users: a worker sees where a job
actually is, and a household sees where an applicant actually is, without
waiting for a hire. Both sides need the map to judge whether a job is worth
travelling to at all, so gating it until hire made the distance map empty at
exactly the moment it was useful.

Signed-out visitors are the exception. Job list and detail are readable
without an account, so anonymous callers still get the ~1 km approximate
point and a barangay-level label -- otherwise every household's home address
would be scrapable from the public job feed.

Contact details (the household's phone/email) are *not* location data and
stay gated on a real hire: knowing where a job is does not require being able
to call the person who posted it.
"""

from apps.common.barangays import CITY, PROVINCE, barangay_from_location_label
from apps.jobs.models import JobApplication

HIRED_STATUSES = frozenset({JobApplication.STATUS_HIRED, JobApplication.STATUS_COMPLETED})

UNAVAILABLE_DISTANCE_LABEL = "Road distance unavailable"

# 0.01 degrees is ~1.1 km of latitude (~1.08 km of longitude at Tayabas' 14 N).
# Snapping to a fixed grid, rather than adding random noise that averages
# away over repeated requests, puts a job in its neighbourhood on the Find
# Jobs map without pointing at the household's house.
APPROXIMATE_GRID_DEGREES = 0.01


def hire_reveals_contact(application, viewer):
    """True only for the two parties of this specific hire -- the hired
    worker and that job's household -- once the application is hired (or
    completed after being hired). Anyone else, and every pending, rejected,
    closed or hire-requested application, gets False.

    Governs the household's phone and email only. Locations went back to
    being visible to any signed-in participant; contact details did not.
    """
    if viewer is None or not getattr(viewer, "is_authenticated", False):
        return False
    if application.status not in HIRED_STATUSES:
        return False
    return viewer.id in (application.worker_id, application.job.household_id)


def viewer_can_see_locations(viewer):
    """Exact coordinates, road routes and full location labels are shared
    with any signed-in user. Anonymous callers get the approximate point and
    the barangay label instead -- the job feed is public, so anything exact
    here would be readable without an account."""
    return viewer is not None and bool(getattr(viewer, "is_authenticated", False))


def rounded_distance_km(distance_km):
    """0.1 km (~100 m) resolution: enough to compare candidates, too coarse
    to pin down a home from the known job site."""
    return round(distance_km, 1) if distance_km is not None else None


def approximate_coordinate(value):
    """A coordinate snapped to the ~1 km grid, safe to show any worker."""
    if value is None:
        return None
    return round(round(float(value) / APPROXIMATE_GRID_DEGREES) * APPROXIMATE_GRID_DEGREES, 4)


def masked_location_label(location_label):
    """A job's location cut down to its barangay.

    The coordinates were already withheld until hire, but the free-text label
    carries whatever the household typed -- often a house number and street --
    and it was going out to anyone, signed in or not. A worker deciding
    whether to apply needs the neighbourhood, not the doorstep.
    """
    barangay = barangay_from_location_label(location_label)
    if not barangay:
        return CITY
    return f"{barangay}, {CITY}, {PROVINCE}"


def distance_label(distance_km):
    if distance_km is None:
        return UNAVAILABLE_DISTANCE_LABEL
    if distance_km < 1:
        return "Within 1 km"
    return f"{distance_km:.1f} km away"
