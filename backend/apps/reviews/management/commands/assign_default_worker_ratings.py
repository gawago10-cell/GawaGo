from django.core.management.base import BaseCommand, CommandError

from apps.reviews.services import assign_default_worker_ratings


class Command(BaseCommand):
    help = "Assign default 3.5-star worker ratings for completed jobs with no household feedback."

    def add_arguments(self, parser):
        parser.add_argument(
            "--after-hours",
            type=int,
            default=72,
            help="Assign defaults after this many hours since job completion. Must be at least 48.",
        )
        parser.add_argument(
            "--dry-run",
            action="store_true",
            help="Report how many ratings would be created without writing them.",
        )

    def handle(self, *args, **options):
        after_hours = options["after_hours"]
        if after_hours < 48:
            raise CommandError("--after-hours must be at least 48.")

        created_count = assign_default_worker_ratings(after_hours=after_hours, dry_run=options["dry_run"])
        action = "would be assigned" if options["dry_run"] else "assigned"
        self.stdout.write(self.style.SUCCESS(f"{created_count} default worker rating(s) {action}."))
