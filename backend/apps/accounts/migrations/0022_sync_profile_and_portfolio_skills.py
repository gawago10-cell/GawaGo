from django.db import migrations

MAX_WORKER_SKILLS = 3
SKILL_NAME_MAX_LENGTH = 120


def _name(value):
    return " ".join(str(value or "").split())[:SKILL_NAME_MAX_LENGTH]


def _key(value):
    return _name(value).casefold()


def sync_skills(apps, schema_editor):
    """Bring each worker's two skill lists into step without changing what
    they chose to be matched on, beyond skills they added themselves.

    - A portfolio skill the worker added (no household rating on it) joins the
      profile list while the 3-skill cap has room, oldest first.
    - Rated portfolio skills that are not on the profile list stay off it: a
      household creates such a row when it rates work the worker never
      listed, and that must not start matching the worker to those jobs.
    - Every profile skill gets a portfolio entry with no stated proficiency.
    - Names longer than the portfolio column are trimmed to fit.
    Nothing is deleted.
    """
    UserProfile = apps.get_model("accounts", "UserProfile")
    WorkerSkill = apps.get_model("accounts", "WorkerSkill")
    SkillRating = apps.get_model("accounts", "SkillRating")
    rated_skill_ids = set(SkillRating.objects.values_list("skill_id", flat=True))
    for profile in UserProfile.objects.filter(role="worker"):
        original = list(profile.skills or [])
        listed = []
        listed_keys = set()
        for value in original:
            name = _name(value)
            if name and name.casefold() not in listed_keys:
                listed.append(name)
                listed_keys.add(name.casefold())
        rows = list(WorkerSkill.objects.filter(worker_id=profile.user_id).order_by("created_at", "id"))
        for row in rows:
            if len(listed) >= MAX_WORKER_SKILLS:
                break
            if row.id in rated_skill_ids:
                continue
            if _key(row.skill_name) not in listed_keys:
                listed.append(_name(row.skill_name))
                listed_keys.add(_key(row.skill_name))
        if listed != original:
            profile.skills = listed
            profile.save(update_fields=["skills"])
        have = {_key(row.skill_name) for row in rows}
        for name in listed:
            if name.casefold() not in have:
                WorkerSkill.objects.create(worker_id=profile.user_id, skill_name=name, proficiency="")
                have.add(name.casefold())


class Migration(migrations.Migration):
    dependencies = [
        ("accounts", "0021_workerskill_proficiency_blank"),
    ]

    # The reverse is a no-op: it only ever added a worker's own unrated
    # portfolio skills to their list and created portfolio entries, both of
    # which are harmless to keep after rolling back the code.
    operations = [
        migrations.RunPython(sync_skills, migrations.RunPython.noop),
    ]
