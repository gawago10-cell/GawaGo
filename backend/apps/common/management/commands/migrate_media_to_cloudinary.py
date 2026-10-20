"""Uploads existing PUBLIC media to Cloudinary and rewrites the database
paths to the returned public_ids.

Private media (government IDs, worker certificates, complaint evidence) is
deliberately not touched: those stay on local disk behind permission-checked
views, because a Cloudinary delivery URL is public to anyone holding it.

    python manage.py migrate_media_to_cloudinary --dry-run
    python manage.py migrate_media_to_cloudinary
"""

from pathlib import Path

from django.conf import settings
from django.core.files.base import ContentFile
from django.core.management.base import BaseCommand, CommandError


def _public_media_fields():
    """(model, field_name) for every upload that is safe to make public."""
    from apps.accounts.models import UserProfile, WorkerPortfolioItem
    from apps.jobs.models import JobImage

    return [
        (UserProfile, "profile_photo"),
        (WorkerPortfolioItem, "image"),
        (WorkerPortfolioItem, "before_image"),
        (WorkerPortfolioItem, "after_image"),
        (JobImage, "image"),
    ]


class Command(BaseCommand):
    help = "Upload existing public media to Cloudinary and repoint the database at it."

    def add_arguments(self, parser):
        parser.add_argument(
            "--dry-run",
            action="store_true",
            help="List what would be uploaded without changing anything.",
        )

    def handle(self, *args, **options):
        if not options["dry_run"] and not settings.USE_CLOUDINARY:
            raise CommandError(
                "USE_CLOUDINARY is False, so the default storage is still local disk "
                "and uploads would not reach Cloudinary. Set it to True first."
            )

        from apps.common.cloudinary_storage import CloudinaryMediaStorage

        storage = CloudinaryMediaStorage()
        media_root = Path(settings.MEDIA_ROOT)
        uploaded = skipped = missing = 0

        for model, field_name in _public_media_fields():
            rows = model.objects.exclude(**{field_name: ""}).exclude(**{f"{field_name}__isnull": True})
            for row in rows.iterator():
                current = getattr(row, field_name)
                name = current.name
                if not name:
                    continue
                # Anything without a local counterpart is already remote.
                source = media_root / name
                if not source.exists():
                    self.stdout.write(f"  already remote / missing locally: {name}")
                    missing += 1
                    continue
                if options["dry_run"]:
                    self.stdout.write(f"  would upload: {name} ({source.stat().st_size} bytes)")
                    skipped += 1
                    continue
                stored = storage._save(name, ContentFile(source.read_bytes()))
                setattr(row, field_name, stored)
                row.save(update_fields=[field_name])
                self.stdout.write(self.style.SUCCESS(f"  uploaded: {name} -> {stored}"))
                uploaded += 1

        summary = (
            f"dry run: {skipped} file(s) would be uploaded, {missing} already remote/missing"
            if options["dry_run"]
            else f"uploaded {uploaded} file(s); {missing} already remote/missing"
        )
        self.stdout.write(self.style.SUCCESS(summary))
        self.stdout.write(
            "Private media (IDs, certificates, complaint evidence) was not touched, by design."
        )
