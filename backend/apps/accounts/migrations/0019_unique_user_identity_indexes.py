"""Case-insensitive unique indexes on the account's username and email.

The registration view checked for duplicates with a query first, which races:
two simultaneous signups both passed the check, and with no index behind it
the database happily created two accounts sharing one email -- breaking
login-by-email and password reset for both.

auth.User is not ours to add Meta constraints to, so the indexes go on
auth_user directly. Expression indexes need PostgreSQL or SQLite; MySQL
(before 8.0.13) cannot do them, so there the view's check plus its
IntegrityError handling remain the only guard.
"""

from django.db import migrations

USERNAME_INDEX = "accounts_user_username_lower_uniq"
EMAIL_INDEX = "accounts_user_email_lower_uniq"
SUPPORTED_VENDORS = {"postgresql", "sqlite"}


def _duplicate_report(cursor, column):
    cursor.execute(
        f"SELECT LOWER({column}), COUNT(*) FROM auth_user "
        f"WHERE {column} <> '' GROUP BY LOWER({column}) HAVING COUNT(*) > 1"
    )
    return cursor.fetchall()


def create_indexes(apps, schema_editor):
    connection = schema_editor.connection
    if connection.vendor not in SUPPORTED_VENDORS:
        return
    with connection.cursor() as cursor:
        for column, index in (("username", USERNAME_INDEX), ("email", EMAIL_INDEX)):
            duplicates = _duplicate_report(cursor, column)
            if duplicates:
                listed = ", ".join(f"{value} x{count}" for value, count in duplicates)
                raise RuntimeError(
                    f"Cannot add a unique index on LOWER({column}): existing duplicates "
                    f"({listed}). Merge or rename those accounts first."
                )
            # Empty emails are excluded: a superuser created without one is
            # valid, and several of them must not collide.
            cursor.execute(
                f"CREATE UNIQUE INDEX IF NOT EXISTS {index} "
                f"ON auth_user (LOWER({column})) WHERE {column} <> ''"
            )


def drop_indexes(apps, schema_editor):
    connection = schema_editor.connection
    if connection.vendor not in SUPPORTED_VENDORS:
        return
    with connection.cursor() as cursor:
        for index in (USERNAME_INDEX, EMAIL_INDEX):
            cursor.execute(f"DROP INDEX IF EXISTS {index}")


class Migration(migrations.Migration):
    dependencies = [("accounts", "0018_repair_mangled_skills")]

    operations = [migrations.RunPython(create_indexes, drop_indexes)]
