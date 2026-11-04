from django.db import migrations


def record_existing_bans(apps, schema_editor):
    """Accounts already blocked permanently before BannedCredential existed
    get their rows now, so a ban made last week also stops a new signup."""
    from apps.accounts.banned import normalize_email, normalize_id_number, normalize_name, normalize_phone

    UserProfile = apps.get_model("accounts", "UserProfile")
    BannedCredential = apps.get_model("accounts", "BannedCredential")
    VerificationRequest = apps.get_model("common", "VerificationRequest")
    for profile in UserProfile.objects.filter(is_blocked=True, blocked_until__isnull=True).select_related("user"):
        user = profile.user
        full_name = f"{user.first_name} {user.last_name}"
        pairs = [
            ("email", normalize_email(user.email)),
            ("phone", normalize_phone(profile.phone)),
            ("name", normalize_name(full_name)),
        ]
        for number in VerificationRequest.objects.filter(worker_id=user.id).values_list("primary_id_number", flat=True):
            pairs.append(("id_number", normalize_id_number(number)))
        for kind, value in dict.fromkeys(pair for pair in pairs if pair[1]):
            if not BannedCredential.objects.filter(user_id=user.id, kind=kind, value=value).exists():
                BannedCredential.objects.create(kind=kind, value=value, user_id=user.id, username=user.username)


class Migration(migrations.Migration):
    dependencies = [
        ("accounts", "0024_banned_credentials"),
        ("common", "0009_verification_id_number"),
    ]

    operations = [migrations.RunPython(record_existing_bans, migrations.RunPython.noop)]
