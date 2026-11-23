"""Demo data for the capstone defense: people of Tayabas City and jobs in
every state, so the live system looks lived-in.

    DEMO_PASSWORD=... python manage.py seed_defense_demo [--reset]

Re-runnable: accounts are matched by username and their jobs by title, and
dates are counted from today, so a run in December reads the same as one in
November. --reset first deletes every demo account (and what hangs off it)
and builds them again. Only demo accounts are touched; their emails are
gawago10+demo.<username>@gmail.com, the project's own inbox, so a
notification email from the live site never reaches a stranger.

The password comes from the DEMO_PASSWORD environment variable (or
--password), never from the repository.
"""

import io
import os
from datetime import datetime, time, timedelta
from decimal import Decimal

from django.contrib.auth.models import User
from django.core.files.base import ContentFile
from django.core.management.base import BaseCommand, CommandError
from django.db import transaction
from django.db.models import Q
from django.utils import timezone

from apps.accounts.models import UserProfile, WorkerCertification, WorkerPortfolioItem
from apps.accounts.services import ensure_portfolio_skills
from apps.chat.models import Message
from apps.common.barangays import BARANGAY_CENTERS
from apps.common.models import VerificationRequest
from apps.common.tayabas_boundary import is_inside_tayabas
from apps.complaints.models import Complaint
from apps.jobs.models import JobApplication, JobPosting, JobStatusEvent
from apps.jobs.serializers import BOUNDARY_TO_KM
from apps.notifications.models import Notification
from apps.notifications.services import create_notification
from apps.reviews.models import Review
from apps.reviews.services import recalculate_user_rating, round_rating

EMAIL_PREFIX = "gawago10+demo."

# (username, first, last, barangay, street, verification stage)
HOUSEHOLDS = [
    ("liza.mendoza", "Liza", "Mendoza", "San Diego Zone I", "12 Quezon Ave", "verified"),
    ("ramon.villanueva", "Ramon", "Villanueva", "San Isidro Zone I", "45 Rizal St", "verified"),
    ("grace.bautista", "Grace", "Bautista", "Angeles Zone II", "8 Mabini St", "verified"),
    ("fernando.cruz", "Fernando", "Cruz", "Ipilan", "23 Bonifacio St", "verified"),
    ("teresa.ramos", "Teresa", "Ramos", "Lalo", "5 Luna St", "pending_review"),
    ("paolo.garcia", "Paolo", "Garcia", "Wakas", "17 Del Pilar St", "not_submitted"),
]

# (username, first, last, barangay, street, skills, hourly, daily, years, stage, bio)
WORKERS = [
    ("maria.santos", "Maria", "Santos", "San Roque Zone I", "3 Burgos St", ["House Cleaning", "Laundry"],
     None, "650", 6, "verified", "Six years of house cleaning and laundry for families in the poblacion."),
    ("jose.delarosa", "Jose", "Dela Rosa", "San Isidro Zone III", "60 Rizal St", ["Plumbing", "Carpentry"],
     "150", "900", 10, "verified", "Plumber and carpenter. Leaks, sinks, cabinets and small repairs."),
    ("ana.villareal", "Ana", "Villareal", "San Isidro Zone II", "14 Lopez St", ["Cooking", "Childcare"],
     None, "700", 4, "verified", "Home cook for parties and everyday meals; also looks after children."),
    ("mark.aquino", "Mark", "Aquino", "Angustias Zone I", "9 Palma St", ["Electrical Work", "Aircon Repair"],
     "200", "1100", 8, "verified", "Licensed electrician. Wiring, outlets and aircon cleaning."),
    ("rosa.lim", "Rosa", "Lim", "San Diego Zone II", "21 Quezon Ave", ["Elder Care", "Cooking"],
     None, "750", 5, "verified", "Caregiver for elderly family members, with meal preparation."),
    ("carlo.navarro", "Carlo", "Navarro", "Ipilan", "30 Bonifacio St", ["Gardening", "Driving"],
     None, "600", 3, "verified", "Gardening, landscaping and a family driver when needed."),
    ("joy.fernandez", "Joy", "Fernandez", "Angeles Zone I", "2 Mabini St", ["House Cleaning", "Cooking"],
     None, "600", 2, "pending_review", "New to GawaGo. House cleaning and cooking."),
    ("ben.torres", "Ben", "Torres", "Lalo", "11 Luna St", ["Painting", "Welding"],
     None, "850", 7, "rejected", "House painting and gate welding."),
    ("lea.morales", "Lea", "Morales", "Wakas", "19 Del Pilar St", ["Laundry"],
     None, "500", 1, "not_submitted", "Laundry, washing and ironing."),
    ("rico.salazar", "Rico", "Salazar", "San Roque Zone II", "7 Burgos St", ["Carpentry", "Painting"],
     None, "900", 9, "verified", "Carpenter and painter. Furniture, shelves and repainting."),
]

# key: household, title, skill, schedule type, start/end (days from today),
# rate, rate type, worker slots, radius, status, description,
# applications as (worker, status, invited)
JOBS = {
    "weekly_cleaning": dict(
        household="liza.mendoza", title="Weekly house cleaning", skill="House Cleaning", schedule="One-Time",
        start=5, end=5, rate="700", rate_type="per_day", slots=1, radius="5km", status="open",
        description="Sweep, mop and dust a two-storey house. Cleaning supplies are provided.",
        applications=[("maria.santos", "pending", False)],
    ),
    "fiesta_cooking": dict(
        household="grace.bautista", title="Fiesta cooking helpers", skill="Cooking", schedule="One-Time",
        start=9, end=10, rate="750", rate_type="per_day", slots=2, radius="5km", status="open",
        description="Two cooks for our barangay fiesta: pancit, lechon kawali and kakanin for about 60 guests.",
        applications=[("ana.villareal", "pending", False), ("rosa.lim", "hire_requested", True)],
    ),
    "sink_repair": dict(
        household="ramon.villanueva", title="Kitchen sink repair", skill="Plumbing", schedule="One-Time",
        start=3, end=3, rate="900", rate_type="per_day", slots=1, radius="5km", status="assigned",
        description="The kitchen sink leaks under the cabinet and drains slowly.",
        applications=[("jose.delarosa", "hired", False)],
    ),
    "garden_makeover": dict(
        household="fernando.cruz", title="Garden makeover", skill="Gardening", schedule="Part-Time",
        start=-1, end=1, rate="600", rate_type="per_day", slots=1, radius="5km", status="assigned",
        description="Trim the hedges, clear the weeds and plant the new ornamental plants.",
        applications=[("carlo.navarro", "hired", False)],
    ),
    "laundry_week": dict(
        household="fernando.cruz", title="Laundry for the week", skill="Laundry", schedule="One-Time",
        start=-4, end=-3, rate="500", rate_type="per_day", slots=1, radius="5km", status="assigned",
        description="Wash, dry and iron a week of clothes for a family of five.",
        applications=[("maria.santos", "hired", False)],
    ),
    "aircon_cleaning": dict(
        household="ramon.villanueva", title="Aircon cleaning", skill="Aircon Repair", schedule="One-Time",
        start=-20, end=-20, rate="1100", rate_type="per_day", slots=1, radius="5km", status="completed",
        description="Clean two window-type aircon units before summer.",
        applications=[("mark.aquino", "completed", False)],
    ),
    "elder_care": dict(
        household="liza.mendoza", title="Weekend elder care", skill="Elder Care", schedule="One-Time",
        start=-15, end=-14, rate="750", rate_type="per_day", slots=1, radius="5km", status="completed",
        description="Look after my mother over the weekend: meals, medicine and a short walk.",
        applications=[("rosa.lim", "completed", False)],
    ),
    "deep_cleaning": dict(
        household="grace.bautista", title="Deep cleaning before the fiesta", skill="House Cleaning",
        schedule="One-Time", start=-30, end=-30, rate="650", rate_type="per_day", slots=1, radius="5km",
        status="completed", description="Deep clean the kitchen, living room and windows.",
        applications=[("maria.santos", "completed", False)],
    ),
    "fence_painting": dict(
        household="fernando.cruz", title="Fence painting", skill="Painting", schedule="One-Time",
        start=-12, end=-11, rate="850", rate_type="per_day", slots=1, radius="5km", status="completed",
        description="Repaint the front fence and gate. Paint is provided.",
        applications=[("rico.salazar", "completed", False)],
    ),
    "laundry_pickup": dict(
        household="grace.bautista", title="Laundry pickup", skill="Laundry", schedule="One-Time",
        start=2, end=2, rate="450", rate_type="per_day", slots=1, radius="5km", status="cancelled",
        description="Pick up, wash and fold two baskets of laundry.", applications=[],
    ),
    "cabinet_repair": dict(
        household="ramon.villanueva", title="Cabinet repair", skill="Carpentry", schedule="One-Time",
        start=-45, end=-44, rate="900", rate_type="per_day", slots=1, radius="5km", status="completed",
        description="Fix two kitchen cabinet doors and a loose drawer.",
        applications=[("jose.delarosa", "completed", False)],
    ),
    "window_cleaning": dict(
        household="liza.mendoza", title="Window cleaning", skill="House Cleaning", schedule="One-Time",
        start=-75, end=-75, rate="600", rate_type="per_day", slots=1, radius="5km", status="completed",
        description="Clean all windows and screens, inside and out.",
        applications=[("maria.santos", "completed", False)],
    ),
    "outlet_fix": dict(
        household="ramon.villanueva", title="Electrical outlet fix", skill="Electrical Work", schedule="One-Time",
        start=6, end=6, rate="250", rate_type="per_hour", slots=1, radius="5km", status="open",
        description="Two outlets in the bedroom stopped working.", applications=[],
    ),
    "bookshelf": dict(
        household="grace.bautista", title="Build a bookshelf", skill="Carpentry", schedule="One-Time",
        start=12, end=13, rate="900", rate_type="per_day", slots=1, radius="10km", status="open",
        description="Build a wooden bookshelf for the living room. Wood is provided.",
        applications=[("rico.salazar", "pending", False)],
    ),
    "weekend_babysitter": dict(
        household="liza.mendoza", title="Babysitter for the weekend", skill="Childcare", schedule="Part-Time",
        start=7, end=8, rate="700", rate_type="per_day", slots=1, radius="5km", status="open",
        description="Look after two children, ages 4 and 7, from 8 AM to 5 PM.", applications=[],
    ),
}

# job, author, rating (or None), metrics (quality, punctuality, communication, professionalism), feedback
HOUSEHOLD_REVIEWS = [
    ("aircon_cleaning", 5, (5, 4, 5, 5), "Malinis ang trabaho at maagang dumating."),
    ("elder_care", 5, (5, 5, 4, 4), "Mabait at maalaga kay Nanay."),
    ("deep_cleaning", 5, None, "Very thorough. The kitchen looks new."),
    ("cabinet_repair", 4, None, "Good work, finished a bit late."),
    ("window_cleaning", 5, None, "Spotless windows. Will hire again."),
]
WORKER_REVIEWS = [
    ("aircon_cleaning", 5, "Malinaw ang bilin at mabait."),
    ("elder_care", 4, "Organized household, paid on time."),
    ("deep_cleaning", 5, "Friendly family, everything was ready."),
    ("fence_painting", 4, "Paint was ready when I arrived."),
    ("cabinet_repair", 5, "Clear instructions."),
    ("window_cleaning", 5, "Very welcoming."),
]

CHATS = {
    "sink_repair": [
        ("ramon.villanueva", "Magandang araw! Pwede ka ba ng 8 AM sa araw ng trabaho?"),
        ("jose.delarosa", "Opo, darating po ako ng 8 AM. Dadalhin ko na ang mga gamit."),
    ],
    "garden_makeover": [
        ("carlo.navarro", "Nandito na po ako. Saan ko ilalagay ang mga bagong halaman?"),
        ("fernando.cruz", "Sa tabi ng gate, salamat!"),
    ],
}

# complainant, respondent, job, type, status, description, resolution
COMPLAINTS = [
    ("fernando.cruz", "rico.salazar", "fence_painting", Complaint.TYPE_QUALITY_OF_WORK, Complaint.STATUS_SUBMITTED,
     "Some parts of the fence near the gate were left unpainted.", ""),
    ("carlo.navarro", "fernando.cruz", "garden_makeover", Complaint.TYPE_PAYMENT_ISSUE, Complaint.STATUS_UNDER_REVIEW,
     "We agreed on PHP 600 a day, but the household now wants to pay less.", ""),
    ("mark.aquino", "ramon.villanueva", "aircon_cleaning", Complaint.TYPE_OTHER, Complaint.STATUS_RESOLVED,
     "The schedule was changed twice without notice.",
     "We spoke with both sides. The household agreed to confirm schedules a day ahead."),
]


def _email(username):
    return f"{EMAIL_PREFIX}{username}@gmail.com"


def _pin(barangay, index):
    """A point near the barangay's centre, spread a little so pins don't
    stack, and always inside the city boundary."""
    centre = BARANGAY_CENTERS[barangay]
    offsets = [(0.0012, 0.0008), (-0.0010, 0.0011), (0.0009, -0.0012), (-0.0013, -0.0007)]
    d_lat, d_lng = offsets[index % len(offsets)]
    lat, lng = centre["latitude"] + d_lat, centre["longitude"] + d_lng
    if not is_inside_tayabas(lat, lng):
        lat, lng = centre["latitude"], centre["longitude"]
    return Decimal(f"{lat:.7f}"), Decimal(f"{lng:.7f}")


def _png(title, lines, size=(640, 400), colour=(233, 239, 220)):
    """A plain card image marked as demo material (never a real ID)."""
    from PIL import Image, ImageDraw

    image = Image.new("RGB", size, colour)
    draw = ImageDraw.Draw(image)
    draw.rectangle([10, 10, size[0] - 10, size[1] - 10], outline=(92, 122, 52), width=4)
    draw.text((30, 30), title, fill=(31, 42, 25))
    for row, line in enumerate(lines):
        draw.text((30, 80 + row * 30), line, fill=(31, 42, 25))
    draw.text((30, size[1] - 50), "DEMO DOCUMENT - NOT A REAL ID OR CERTIFICATE", fill=(181, 87, 62))
    buffer = io.BytesIO()
    image.save(buffer, format="PNG")
    return buffer.getvalue()


def _delete_with_files(queryset, *fields):
    """Delete records and their stored files (Cloudinary on the live site),
    so a re-run doesn't leave the old images behind."""
    for record in queryset:
        for field in fields:
            stored = getattr(record, field)
            if stored:
                stored.delete(save=False)
        record.delete()


def _at(day, hour=9):
    return timezone.make_aware(datetime.combine(day, time(hour, 0)))


class Command(BaseCommand):
    help = "Seed the capstone-defense demo: Tayabas households, workers and jobs in every state."

    def add_arguments(self, parser):
        parser.add_argument("--reset", action="store_true", help="Delete every demo account first, then rebuild.")
        parser.add_argument("--password", default="", help="Demo password (else the DEMO_PASSWORD env variable).")

    def handle(self, *args, **options):
        password = options["password"] or os.environ.get("DEMO_PASSWORD", "")
        if len(password) < 8:
            raise CommandError("Set DEMO_PASSWORD (at least 8 characters) or pass --password.")
        with transaction.atomic():
            if options["reset"]:
                self._reset()
            self.today = timezone.localdate()
            self.users = {}
            self._accounts(password)
            self.jobs, self.applications = {}, {}
            self._jobs()
            self._reviews()
            self._chats()
            self._complaints()
            self._documents()
            self._notifications()
            for user in self.users.values():
                recalculate_user_rating(user)
        self.stdout.write(self.style.SUCCESS(
            f"Demo ready: {len(HOUSEHOLDS)} households, {len(WORKERS)} workers, {len(JOBS)} jobs."
        ))

    # ---- accounts ----

    def _reset(self):
        demo_users = User.objects.filter(email__startswith=EMAIL_PREFIX)
        _delete_with_files(VerificationRequest.objects.filter(worker__in=demo_users),
                           "primary_id_file", "secondary_doc_file")
        _delete_with_files(WorkerCertification.objects.filter(worker__in=demo_users), "certificate_file")
        _delete_with_files(WorkerPortfolioItem.objects.filter(worker__in=demo_users),
                           "image", "before_image", "after_image")
        Complaint.objects.filter(Q(complainant__in=demo_users) | Q(respondent__in=demo_users)).delete()
        Review.objects.filter(Q(author__in=demo_users) | Q(target__in=demo_users)).delete()
        demo_users.delete()

    def _accounts(self, password):
        for index, (username, first, last, barangay, street, stage) in enumerate(HOUSEHOLDS):
            user = self._user(username, first, last, password)
            self._profile(user, UserProfile.ROLE_HOUSEHOLD, barangay, street, stage, index, f"99900010{index:02d}")
        for index, row in enumerate(WORKERS):
            username, first, last, barangay, street, skills, hourly, daily, years, stage, bio = row
            user = self._user(username, first, last, password)
            profile = self._profile(
                user, UserProfile.ROLE_WORKER, barangay, street, stage, index + 1, f"99900020{index:02d}"
            )
            profile.skills = skills
            profile.hourly_rate = Decimal(hourly) if hourly else None
            profile.daily_rate = Decimal(daily) if daily else None
            profile.years_experience = years
            profile.bio = bio
            profile.save()
            ensure_portfolio_skills(user, skills)

    def _user(self, username, first, last, password):
        user, _ = User.objects.get_or_create(username=username, defaults={"email": _email(username)})
        user.email = _email(username)
        user.first_name, user.last_name = first, last
        user.is_active, user.is_staff, user.is_superuser = True, False, False
        user.set_password(password)
        user.save()
        self.users[username] = user
        return user

    def _profile(self, user, role, barangay, street, stage, index, phone):
        profile, _ = UserProfile.objects.get_or_create(user=user, defaults={"role": role})
        latitude, longitude = _pin(barangay, index)
        profile.role = role
        profile.phone = phone
        profile.location_label = f"{barangay}, {street}"
        profile.latitude, profile.longitude = latitude, longitude
        profile.verification_status = {"verified": "verified", "rejected": "rejected"}.get(stage, "pending")
        profile.is_blocked = False
        profile.save()
        return profile

    # ---- jobs ----

    def _jobs(self):
        for key, data in JOBS.items():
            household = self.users[data["household"]]
            profile = household.profile
            start = self.today + timedelta(days=data["start"])
            end = self.today + timedelta(days=data["end"])
            job, _ = JobPosting.objects.update_or_create(
                household=household,
                title=data["title"],
                defaults={
                    "job_type": data["skill"],
                    "required_skill": data["skill"],
                    "schedule": data["schedule"],
                    "schedule_type": data["schedule"],
                    "description": data["description"],
                    "location_label": profile.location_label,
                    "latitude": profile.latitude,
                    "longitude": profile.longitude,
                    "service_rate": Decimal(data["rate"]),
                    "rate_type": data["rate_type"],
                    "worker_slots": data["slots"],
                    "status": data["status"],
                    "job_start_date": start,
                    "job_end_date": end,
                    "estimated_working_days": (end - start).days + 1,
                    "geographic_boundary": data["radius"],
                    "max_distance_km": BOUNDARY_TO_KM[data["radius"]],
                    "completed_at": _at(end + timedelta(days=1), 17) if data["status"] == "completed" else None,
                },
            )
            posted = _at(min(start, self.today) - timedelta(days=7 if data["start"] < 0 else 2), 8)
            JobPosting.objects.filter(pk=job.pk).update(created_at=posted)
            job.applications.exclude(worker__username__in=[a[0] for a in data["applications"]]).delete()
            job.status_events.all().delete()
            if data["status"] == "cancelled":
                JobStatusEvent.objects.create(
                    job=job, entity=JobStatusEvent.ENTITY_JOB, from_status="open", to_status="cancelled",
                    actor=household, note="Our family moved the schedule to next month.",
                )
            for worker_name, status, invited in data["applications"]:
                application, _ = JobApplication.objects.update_or_create(
                    job=job,
                    worker=self.users[worker_name],
                    defaults={"status": status, "note": "" if invited else "Available on those dates."},
                )
                applied = posted + timedelta(hours=20)
                JobApplication.objects.filter(pk=application.pk).update(applied_at=applied)
                if invited:
                    event = JobStatusEvent.objects.create(
                        job=job, application=application, entity=JobStatusEvent.ENTITY_APPLICATION,
                        from_status="pending", to_status="hire_requested", actor=household,
                    )
                    JobStatusEvent.objects.filter(pk=event.pk).update(created_at=applied)
                self.applications[(key, worker_name)] = application
            self.jobs[key] = job

    def _reviews(self):
        for key, rating, metrics, feedback in HOUSEHOLD_REVIEWS:
            job = self.jobs[key]
            worker = job.applications.get(status="completed").worker
            fields = {"rating": Decimal(rating), "feedback": feedback, "job_title": job.title,
                      "author_role": Review.ROLE_HOUSEHOLD, "target_role": Review.ROLE_WORKER,
                      "is_system_generated": False}
            if metrics:
                quality, punctuality, communication, professionalism = metrics
                fields.update(quality_of_work=quality, punctuality=punctuality,
                              communication=communication, professionalism=professionalism)
                fields["rating"] = round_rating(Decimal(sum(metrics)) / 4)
            Review.objects.update_or_create(job=job, author=job.household, target=worker, defaults=fields)
        # The fence job was never rated in time: the automatic 3.5.
        fence = self.jobs["fence_painting"]
        Review.objects.update_or_create(
            job=fence, author=fence.household, target=self.users["rico.salazar"],
            defaults={"rating": Decimal("3.5"), "is_system_generated": True, "job_title": fence.title,
                      "author_role": Review.ROLE_HOUSEHOLD, "target_role": Review.ROLE_WORKER,
                      "feedback": "Default 3.5-star rating assigned because no household feedback was "
                                  "submitted after job completion."},
        )
        for key, rating, feedback in WORKER_REVIEWS:
            job = self.jobs[key]
            worker = job.applications.get(status="completed").worker
            Review.objects.update_or_create(
                job=job, author=worker, target=job.household,
                defaults={"rating": Decimal(rating), "feedback": feedback, "job_title": job.title,
                          "author_role": Review.ROLE_WORKER, "target_role": Review.ROLE_HOUSEHOLD},
            )

    def _chats(self):
        for key, lines in CHATS.items():
            application = self.jobs[key].applications.get(status="hired")
            application.messages.all().delete()
            for offset, (sender, text) in enumerate(lines):
                message = Message.objects.create(application=application, sender=self.users[sender], content=text)
                Message.objects.filter(pk=message.pk).update(
                    created_at=timezone.now() - timedelta(hours=5 - offset), is_read=True
                )

    def _complaints(self):
        for complainant, respondent, key, kind, status, description, resolution in COMPLAINTS:
            Complaint.objects.update_or_create(
                complainant=self.users[complainant],
                respondent=self.users[respondent],
                job=self.jobs[key],
                defaults={"complaint_type": kind, "status": status, "description": description,
                          "resolution": resolution or None},
            )

    # ---- documents ----

    def _documents(self):
        people = [(row[0], row[1], row[2], row[5]) for row in HOUSEHOLDS]
        people += [(row[0], row[1], row[2], row[9]) for row in WORKERS]
        for username, first, last, stage in people:
            user = self.users[username]
            _delete_with_files(VerificationRequest.objects.filter(worker=user),
                               "primary_id_file", "secondary_doc_file")
            if stage == "not_submitted":
                continue
            status = {"verified": "approved", "rejected": "rejected"}.get(stage, "pending")
            request = VerificationRequest(
                worker=user,
                primary_id_type=VerificationRequest.ID_TYPE_NATIONAL,
                primary_id_name=f"demo-id-{username}.png",
                primary_id_number=f"DEMO-{user.pk:04d}-{len(username):02d}",
                secondary_doc_name=f"demo-barangay-clearance-{username}.png",
                status=status,
                notes="Submitted for the demo.",
                review_note=("The ID photo is too blurry to read. Please upload a clearer photo."
                             if status == "rejected" else ""),
                reviewed_by_name="superadmin" if status != "pending" else "",
                reviewed_at=timezone.now() - timedelta(days=60) if status != "pending" else None,
            )
            name = f"{first} {last}"
            request.primary_id_file.save(
                f"demo-id-{username}.png",
                ContentFile(_png("NATIONAL ID (SAMPLE)", [name, "Tayabas City, Quezon"])), save=False,
            )
            request.secondary_doc_file.save(
                f"demo-clearance-{username}.png",
                ContentFile(_png("BARANGAY CLEARANCE (SAMPLE)", [name, "Resident in good standing"])), save=False,
            )
            request.save()
            submitted = timezone.now() - timedelta(days=1 if status == "pending" else 61)
            VerificationRequest.objects.filter(pk=request.pk).update(submitted_at=submitted)

        for username, name, issuer, status in [
            ("maria.santos", "Housekeeping NC II", "TESDA", WorkerCertification.STATUS_APPROVED),
            ("rico.salazar", "Carpentry NC II", "TESDA", WorkerCertification.STATUS_PENDING),
        ]:
            worker = self.users[username]
            _delete_with_files(WorkerCertification.objects.filter(worker=worker, certificate_name=name),
                               "certificate_file")
            certificate = WorkerCertification(
                worker=worker, certificate_type=WorkerCertification.TYPE_TESDA, certificate_name=name,
                issuer=issuer, issue_date=self.today - timedelta(days=400), verification_status=status,
                is_verified=status == WorkerCertification.STATUS_APPROVED,
                verified_at=timezone.now() - timedelta(days=30) if status == WorkerCertification.STATUS_APPROVED else None,
            )
            certificate.certificate_file.save(
                f"demo-certificate-{username}.png",
                ContentFile(_png(f"{issuer} {name} (SAMPLE)", [worker.get_full_name()])), save=False,
            )
            certificate.save()

        maria = self.users["maria.santos"]
        _delete_with_files(WorkerPortfolioItem.objects.filter(worker=maria), "image", "before_image", "after_image")
        item = WorkerPortfolioItem(worker=maria, title="Kitchen deep clean",
                                   description="Before and after a full kitchen clean.")
        before = _png("BEFORE", ["Kitchen counter before cleaning"], colour=(214, 200, 170))
        after = _png("AFTER", ["Kitchen counter after cleaning"], colour=(225, 240, 210))
        item.image.save("demo-kitchen-after.png", ContentFile(after), save=False)
        item.before_image.save("demo-kitchen-before.png", ContentFile(before), save=False)
        item.after_image.save("demo-kitchen-after-2.png", ContentFile(after), save=False)
        item.save()

    # ---- notifications (no emails: these describe what already happened) ----

    def _notifications(self):
        Notification.objects.filter(recipient__in=self.users.values()).delete()

        def note(recipient, actor, kind, title, message, key, application=None, action="", url="", **extra):
            create_notification(
                recipient=self.users[recipient], actor=self.users[actor] if actor else None,
                notification_type=kind, title=title, message=message,
                related_job_id=self.jobs[key].id if key else None,
                related_application_id=application.id if application else None,
                action_type=action, action_url=url, send_email=False, **extra,
            )

        weekly = self.applications[("weekly_cleaning", "maria.santos")]
        note("liza.mendoza", "maria.santos", Notification.TYPE_APPLICATION, "New worker application",
             "Maria Santos applied to Weekly house cleaning.", "weekly_cleaning", weekly,
             Notification.ACTION_JOB_DETAIL, f"/household/jobs/{weekly.job_id}")
        fiesta = self.applications[("fiesta_cooking", "ana.villareal")]
        note("grace.bautista", "ana.villareal", Notification.TYPE_APPLICATION, "New worker application",
             "Ana Villareal applied to Fiesta cooking helpers.", "fiesta_cooking", fiesta,
             Notification.ACTION_JOB_DETAIL, f"/household/jobs/{fiesta.job_id}")
        invite = self.applications[("fiesta_cooking", "rosa.lim")]
        note("rosa.lim", "grace.bautista", Notification.TYPE_HIRING, "Hire request",
             "Grace Bautista wants to hire you for Fiesta cooking helpers. Please accept or reject this request.",
             "fiesta_cooking", invite, Notification.ACTION_HIRE_REQUEST, f"/worker/jobs/{invite.job_id}",
             requires_action=True)
        for key, worker, household in [("sink_repair", "jose.delarosa", "Ramon Villanueva"),
                                       ("garden_makeover", "carlo.navarro", "Fernando Cruz")]:
            application = self.applications[(key, worker)]
            note(worker, self.jobs[key].household.username, Notification.TYPE_ACCEPTED, "You're hired",
                 f"{household} hired you for {self.jobs[key].title}.", key, application,
                 Notification.ACTION_JOB_DETAIL, f"/worker/jobs/{application.job_id}")
        note("mark.aquino", "ramon.villanueva", Notification.TYPE_REVIEW, "New review received",
             "Ramon Villanueva rated you 4.8 / 5 for Aircon cleaning.", "aircon_cleaning",
             action=Notification.ACTION_REVIEW)
