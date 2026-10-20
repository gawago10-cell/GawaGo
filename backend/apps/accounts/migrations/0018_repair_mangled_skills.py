import json

from django.db import migrations


def _parse(raw):
    text = raw.strip()
    try:
        parsed = json.loads(text)
    except json.JSONDecodeError:
        parsed = None
    if isinstance(parsed, list):
        return [str(item).strip() for item in parsed if str(item).strip()]
    if isinstance(parsed, str):
        return [parsed.strip()] if parsed.strip() else []
    if text.startswith("[") and text.endswith("]"):
        text = text[1:-1]
    return [item.strip() for item in text.split(",") if item.strip()]


def repair(apps, schema_editor):
    UserProfile = apps.get_model("accounts", "UserProfile")
    for profile in UserProfile.objects.all().iterator():
        skills = profile.skills
        if isinstance(skills, str):
            repaired = _parse(skills)
        elif (
            isinstance(skills, list)
            and len(skills) == 1
            and isinstance(skills[0], str)
            and (
                (skills[0].strip().startswith("[") and skills[0].strip().endswith("]"))
                or "," in skills[0]
            )
        ):
            repaired = _parse(skills[0])
        else:
            continue
        profile.skills = repaired[:3]
        profile.save(update_fields=["skills"])


class Migration(migrations.Migration):
    dependencies = [("accounts", "0017_delete_verificationdocument")]

    operations = [migrations.RunPython(repair, migrations.RunPython.noop)]
