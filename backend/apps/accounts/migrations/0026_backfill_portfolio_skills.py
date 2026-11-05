from django.db import migrations


def add_missing_portfolio_skills(apps, schema_editor):
    """Workers who listed skills before the portfolio kept one entry per
    profile skill had none, so their own Skills & Portfolio tab said "Save
    your profile to set a level" and households saw no skills at all on
    their profile. Same rule as apps.accounts.services.ensure_portfolio_skills:
    one entry per listed skill, no proficiency, matched case-insensitively."""
    UserProfile = apps.get_model("accounts", "UserProfile")
    WorkerSkill = apps.get_model("accounts", "WorkerSkill")
    key = lambda name: " ".join(str(name or "").split()).casefold()
    for profile in UserProfile.objects.filter(role="worker"):
        have = {key(name) for name in WorkerSkill.objects.filter(worker_id=profile.user_id).values_list("skill_name", flat=True)}
        for name in profile.skills or []:
            k = key(name)
            if k and k not in have:
                WorkerSkill.objects.create(worker_id=profile.user_id, skill_name=" ".join(str(name).split()), proficiency="")
                have.add(k)


class Migration(migrations.Migration):
    dependencies = [("accounts", "0025_backfill_banned_credentials")]

    operations = [migrations.RunPython(add_missing_portfolio_skills, migrations.RunPython.noop)]
