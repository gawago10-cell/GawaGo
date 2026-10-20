from django.apps import AppConfig


class JobsConfig(AppConfig):
    default_auto_field = "django.db.models.BigAutoField"
    name = "apps.jobs"

    def ready(self):
        from apps.common.file_cleanup import cleanup_files_on_change_and_delete
        from apps.jobs.models import JobImage

        cleanup_files_on_change_and_delete(JobImage, ["image"])
