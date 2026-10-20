from decimal import Decimal

from django.contrib.auth.models import User
from django.core.management.base import BaseCommand
from django.db import transaction
from django.utils import timezone

from apps.accounts.models import UserProfile
from apps.accounts.services import ensure_portfolio_skills
from apps.common.models import VerificationRequest
from apps.jobs.models import JobApplication, JobPosting
from apps.reviews.models import Review


SHARED_DEMO_PASSWORD = "GawaGo123"

DEMO_LOCATIONS = [
    ("Alitao", "14.0537324", "121.5336725"),
    ("Alupay", "14.0580622", "121.6089432"),
    ("Anos", "13.9923262", "121.5687257"),
    ("Ayaas", "14.0332284", "121.6128036"),
    ("Baguio", "14.0213209", "121.5800397"),
    ("Banilad", "14.0436660", "121.6028771"),
    ("Calumpang", "13.9766616", "121.5562070"),
    ("Camaysa", "14.0613117", "121.5521175"),
    ("Dapdap", "14.0598370", "121.5692816"),
    ("Gibanga", "14.0242644", "121.5244830"),
]

NUMBER_WORDS = ["One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine", "Ten"]

HOUSEHOLDS = [
    {
        "username": f"Household {index}",
        "password": SHARED_DEMO_PASSWORD,
        "first_name": "Household",
        "last_name": NUMBER_WORDS[index - 1],
        "email": f"household{index}@gmail.com",
        "phone": f"91700000{index:02d}",
        "barangay": barangay,
        "street": f"Demo Street {index}",
        "lat": lat,
        "lng": lng,
    }
    for index, (barangay, lat, lng) in enumerate(DEMO_LOCATIONS, start=1)
]

WORKER_TEMPLATES = [
    (["House Cleaning", "Laundry"], "120.00", "650.00", 3, "verified", "4.90", 3),
    (["Plumbing", "Carpentry"], "180.00", "900.00", 5, "verified", "4.50", 2),
    (["Electrical Work", "Aircon Repair/Cleaning"], "200.00", "1000.00", 4, "pending", "4.00", 1),
    (["Childcare", "Cooking"], "130.00", "700.00", 2, "rejected", "3.00", 1),
    (["Laundry", "House Cleaning", "Cooking"], "110.00", "600.00", 1, "pending", None, 0),
    (["Gardening", "House Cleaning"], "115.00", "620.00", 2, "verified", "4.70", 2),
    (["Painting", "Carpentry"], "170.00", "850.00", 6, "verified", "4.80", 4),
    (["Elder Care", "Cooking"], "150.00", "780.00", 4, "pending", "4.20", 1),
    (["Welding", "Electrical Work"], "220.00", "1200.00", 7, "verified", "4.60", 3),
    (["Driving", "Other"], "160.00", "800.00", 3, "pending", None, 0),
]

WORKERS = [
    {
        "username": f"Worker{index}",
        "password": SHARED_DEMO_PASSWORD,
        "first_name": "Worker",
        "last_name": NUMBER_WORDS[index - 1],
        "email": f"worker{index}@gmail.com",
        "phone": f"91800000{index:02d}",
        "barangay": DEMO_LOCATIONS[index - 1][0],
        "street": f"Worker Street {index}",
        "lat": DEMO_LOCATIONS[index - 1][1],
        "lng": DEMO_LOCATIONS[index - 1][2],
        "skills": template[0],
        "hourly": template[1],
        "daily": template[2],
        "years": template[3],
        "verification": template[4],
        "rating": template[5],
        "rating_count": template[6],
    }
    for index, template in enumerate(WORKER_TEMPLATES, start=1)
]

JOBS = [
    {"household": "Household 1", "worker": "Worker1", "title": "House Cleaning Help", "skill": "House Cleaning", "status": JobPosting.STATUS_OPEN, "application_status": JobApplication.STATUS_PENDING, "barangay": "Poblacion", "lat": "13.9411000", "lng": "121.5874000", "rate": "700.00", "months_ago": 0},
    {"household": "Household 2", "worker": "Worker2", "title": "Kitchen Plumbing Repair", "skill": "Plumbing", "status": JobPosting.STATUS_COMPLETED, "application_status": JobApplication.STATUS_CLOSED, "barangay": "Isabang", "lat": "13.9633000", "lng": "121.5447000", "rate": "950.00", "months_ago": 1},
    {"household": "Household 3", "worker": "Worker3", "title": "Electrical Outlet Check", "skill": "Electrical Work", "status": JobPosting.STATUS_COMPLETED, "application_status": JobApplication.STATUS_CLOSED, "barangay": "San Roque", "lat": "13.9431000", "lng": "121.5827000", "rate": "1200.00", "months_ago": 2},
    {"household": "Household 4", "worker": "Worker5", "title": "Laundry Assistance", "skill": "Laundry", "status": JobPosting.STATUS_CANCELLED, "application_status": None, "barangay": "Calumpang", "lat": "13.9404000", "lng": "121.5528000", "rate": "500.00", "months_ago": 3},
    {"household": "Household 5", "worker": "Worker4", "title": "Childcare Support", "skill": "Childcare", "status": JobPosting.STATUS_OPEN, "application_status": JobApplication.STATUS_PENDING, "barangay": "Dapdap", "lat": "13.9616000", "lng": "121.6168000", "rate": "750.00", "months_ago": 4},
    {"household": "Household 1", "worker": "Worker5", "title": "Cooking Support", "skill": "Cooking", "status": JobPosting.STATUS_COMPLETED, "application_status": JobApplication.STATUS_CLOSED, "barangay": "Poblacion", "lat": "13.9411000", "lng": "121.5874000", "rate": "650.00", "months_ago": 5},
    {"household": "Household 6", "worker": "Worker6", "title": "Garden Cleanup", "skill": "Gardening", "status": JobPosting.STATUS_OPEN, "application_status": JobApplication.STATUS_PENDING, "barangay": "Del Rosario", "lat": "13.9463000", "lng": "121.5919000", "rate": "680.00", "months_ago": 0},
    {"household": "Household 7", "worker": "Worker7", "title": "Room Repainting", "skill": "Painting", "status": JobPosting.STATUS_ASSIGNED, "application_status": JobApplication.STATUS_HIRED, "barangay": "San Isidro", "lat": "13.9558000", "lng": "121.5763000", "rate": "900.00", "months_ago": 1},
    {"household": "Household 8", "worker": "Worker8", "title": "Elder Care Visit", "skill": "Elder Care", "status": JobPosting.STATUS_COMPLETED, "application_status": JobApplication.STATUS_CLOSED, "barangay": "Bucal", "lat": "13.9328000", "lng": "121.6108000", "rate": "820.00", "months_ago": 2},
    {"household": "Household 9", "worker": "Worker9", "title": "Gate Welding Repair", "skill": "Welding", "status": JobPosting.STATUS_COMPLETED, "application_status": JobApplication.STATUS_CLOSED, "barangay": "Talolong", "lat": "13.8824000", "lng": "121.5526000", "rate": "1300.00", "months_ago": 3},
    {"household": "Household 10", "worker": "Worker10", "title": "Family Driver Needed", "skill": "Driving", "status": JobPosting.STATUS_CANCELLED, "application_status": None, "barangay": "Wakas", "lat": "13.9263000", "lng": "121.6047000", "rate": "850.00", "months_ago": 4},
    {"household": "Household 6", "worker": "Worker1", "title": "Deep Cleaning Follow-up", "skill": "House Cleaning", "status": JobPosting.STATUS_OPEN, "application_status": JobApplication.STATUS_PENDING, "barangay": "Del Rosario", "lat": "13.9463000", "lng": "121.5919000", "rate": "720.00", "months_ago": 5},
]

REVIEWS = [
    {"author": "Household 1", "target": "Worker1", "job_title": "House Cleaning Help", "rating": 5, "feedback": "Reliable and fast."},
    {"author": "Household 2", "target": "Worker2", "job_title": "Kitchen Plumbing Repair", "rating": 5, "feedback": "Very professional."},
    {"author": "Household 3", "target": "Worker3", "job_title": "Electrical Outlet Check", "rating": 4, "feedback": "Solved the issue."},
    {"author": "Household 5", "target": "Worker4", "job_title": "Childcare Support", "rating": 3, "feedback": "Completed basic tasks."},
    {"author": "Household 1", "target": "Worker5", "job_title": "Cooking Support", "rating": 4, "feedback": "Helpful and punctual."},
    {"author": "Household 6", "target": "Worker6", "job_title": "Garden Cleanup", "rating": 5, "feedback": "Clean work and friendly service."},
    {"author": "Household 7", "target": "Worker7", "job_title": "Room Repainting", "rating": 5, "feedback": "Neat finish and on schedule."},
    {"author": "Household 8", "target": "Worker8", "job_title": "Elder Care Visit", "rating": 4, "feedback": "Kind and attentive."},
    {"author": "Household 9", "target": "Worker9", "job_title": "Gate Welding Repair", "rating": 5, "feedback": "Strong repair work."},
]


class Command(BaseCommand):
    help = "Seed GawaGo backend demo users, jobs, reviews, and verification records."

    @transaction.atomic
    def handle(self, *args, **options):
        users = {}
        created_users = 0

        for account in HOUSEHOLDS:
            user, created = self._upsert_user(account, is_staff=False)
            created_users += int(created)
            users[account["username"]] = user
            self._upsert_profile(user, account, UserProfile.ROLE_HOUSEHOLD)

        for account in WORKERS:
            user, created = self._upsert_user(account, is_staff=False)
            created_users += int(created)
            users[account["username"]] = user
            self._upsert_profile(user, account, UserProfile.ROLE_WORKER)

        jobs_created = 0
        for job_data in JOBS:
            job, created = self._upsert_job(users, job_data)
            jobs_created += int(created)
            if job_data["application_status"]:
                JobApplication.objects.update_or_create(
                    job=job,
                    worker=users[job_data["worker"]],
                    defaults={"status": job_data["application_status"], "note": "Demo application"},
                )

        for review_data in REVIEWS:
            self._upsert_review(users, review_data)

        self._upsert_verification(users["Worker3"], VerificationRequest.STATUS_PENDING, "Awaiting admin review.", "")
        self._upsert_verification(users["Worker4"], VerificationRequest.STATUS_REJECTED, "Document image needs resubmission.", "Please upload clearer documents.")

        self.stdout.write(self.style.SUCCESS(f"Seeded backend demo data. New users: {created_users}, new jobs: {jobs_created}."))

    def _upsert_user(self, account, is_staff=False):
        user, created = User.objects.get_or_create(
            username=account["username"],
            defaults={
                "email": account["email"],
                "first_name": account["first_name"],
                "last_name": account["last_name"],
                "is_active": True,
                "is_staff": is_staff,
            },
        )
        user.email = account["email"]
        user.first_name = account["first_name"]
        user.last_name = account["last_name"]
        user.is_active = True
        user.is_staff = is_staff
        user.set_password(account["password"])
        user.save()
        return user, created

    def _upsert_profile(self, user, account, role):
        profile, _ = UserProfile.objects.get_or_create(user=user, defaults={"role": role})
        profile.role = role
        profile.phone = account["phone"]
        profile.location_label = f"{account['barangay']}, {account['street']}"
        profile.latitude = Decimal(account["lat"])
        profile.longitude = Decimal(account["lng"])
        if role == UserProfile.ROLE_WORKER:
            profile.bio = f"Demo profile for {user.get_full_name() or user.username}."
            profile.skills = account["skills"]
            profile.hourly_rate = Decimal(account["hourly"])
            profile.daily_rate = Decimal(account["daily"])
            profile.years_experience = account["years"]
            profile.verification_status = account["verification"]
            profile.average_rating = Decimal(account["rating"]) if account["rating"] else None
            profile.rating_count = account["rating_count"]
        profile.save()
        if role == UserProfile.ROLE_WORKER:
            ensure_portfolio_skills(user, profile.skills)
        return profile

    def _upsert_job(self, users, job_data):
        household = users[job_data["household"]]
        household_profile = getattr(household, "profile", None)
        job_location_label = household_profile.location_label if household_profile and household_profile.location_label else job_data["barangay"]
        job_latitude = household_profile.latitude if household_profile and household_profile.latitude is not None else Decimal(job_data["lat"])
        job_longitude = household_profile.longitude if household_profile and household_profile.longitude is not None else Decimal(job_data["lng"])
        job, created = JobPosting.objects.update_or_create(
            household=household,
            title=job_data["title"],
            defaults={
                "job_type": job_data["skill"],
                "required_skill": job_data["skill"],
                "schedule": "Demo schedule",
                "description": f"Demo {job_data['skill']} request for analytics.",
                "location_label": job_location_label,
                "latitude": job_latitude,
                "longitude": job_longitude,
                "service_rate": Decimal(job_data["rate"]),
                "worker_slots": 1,
                "status": job_data["status"],
            },
        )
        created_at = timezone.now() - timezone.timedelta(days=30 * job_data["months_ago"])
        JobPosting.objects.filter(pk=job.pk).update(created_at=created_at)
        job.refresh_from_db()
        return job, created

    def _upsert_review(self, users, review_data):
        author = users[review_data["author"]]
        target = users[review_data["target"]]
        review = Review.objects.filter(author=author, target=target, job_title=review_data["job_title"]).first()
        if review is None:
            review = Review(author=author, target=target, job_title=review_data["job_title"])
        review.author_role = UserProfile.ROLE_HOUSEHOLD
        review.target_role = UserProfile.ROLE_WORKER
        review.rating = review_data["rating"]
        review.feedback = review_data["feedback"]
        review.save()
        return review

    def _upsert_verification(self, worker, status, notes, review_note):
        request = VerificationRequest.objects.filter(worker=worker).order_by("-submitted_at").first()
        if request is None:
            request = VerificationRequest(worker=worker)
        request.primary_id_name = "Demo Primary ID"
        request.secondary_doc_name = "Demo Supporting Document"
        request.notes = notes
        request.status = status
        request.review_note = review_note
        request.reviewed_at = timezone.now() if status != VerificationRequest.STATUS_PENDING else None
        request.save()
        return request
