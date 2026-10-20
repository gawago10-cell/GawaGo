from django.apps import AppConfig


class AccountsConfig(AppConfig):
    default_auto_field = "django.db.models.BigAutoField"
    name = "apps.accounts"

    def ready(self):
        from apps.common.file_cleanup import cleanup_files_on_change_and_delete
        from apps.accounts.models import UserProfile, WorkerCertification, WorkerPortfolioItem

        cleanup_files_on_change_and_delete(UserProfile, ["profile_photo"])
        cleanup_files_on_change_and_delete(WorkerCertification, ["certificate_file"])
        cleanup_files_on_change_and_delete(
            WorkerPortfolioItem, ["image", "before_image", "after_image"]
        )
