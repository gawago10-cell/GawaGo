from django.db import migrations


def _is_other(value):
    return " ".join(str(value or "").split()).casefold() == "other"


def drop_other_placeholder(apps, schema_editor):
    """"Other" is the registration form's choice for typing a skill outside
    the catalog, but it used to be saved as a skill of its own: it took one of
    the worker's three slots and lowered their match score on every job.

    Drop it wherever the worker listed a real skill beside it. A worker whose
    only skill is "Other" keeps it, since an empty list cannot be matched at
    all; the profile form asks them to name a skill on their next save. The
    unlisted portfolio row is left in place, like any unlisted skill."""
    UserProfile = apps.get_model("accounts", "UserProfile")
    for profile in UserProfile.objects.filter(role="worker"):
        skills = list(profile.skills or [])
        kept = [skill for skill in skills if not _is_other(skill)]
        if kept and kept != skills:
            profile.skills = kept
            profile.save(update_fields=["skills"])


class Migration(migrations.Migration):

    dependencies = [
        ("accounts", "0022_sync_profile_and_portfolio_skills"),
    ]

    operations = [
        migrations.RunPython(drop_other_placeholder, migrations.RunPython.noop),
    ]
