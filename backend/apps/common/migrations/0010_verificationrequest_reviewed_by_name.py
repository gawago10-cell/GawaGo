from django.db import migrations, models


def backfill_reviewers(apps, schema_editor):
    """Decided requests from before this field: take the reviewer from the
    Audit Logs entry that recorded the decision."""
    VerificationRequest = apps.get_model("common", "VerificationRequest")
    AdminActionLog = apps.get_model("common", "AdminActionLog")
    logs = AdminActionLog.objects.filter(
        target_type="verification_request",
        action__in=["verification_approved", "verification_rejected"],
        target_id__isnull=False,
    ).select_related("actor").order_by("created_at")
    for log in logs:
        name = ""
        if log.actor is not None:
            name = f"{log.actor.first_name} {log.actor.last_name}".strip() or log.actor.username
        name = name or log.actor_username
        if name:
            VerificationRequest.objects.filter(pk=log.target_id, reviewed_by_name="").update(reviewed_by_name=name)


class Migration(migrations.Migration):

    dependencies = [
        ("common", "0009_verification_id_number"),
    ]

    operations = [
        migrations.AddField(
            model_name="verificationrequest",
            name="reviewed_by_name",
            field=models.CharField(blank=True, default="", max_length=255),
        ),
        migrations.RunPython(backfill_reviewers, migrations.RunPython.noop),
    ]
