import uuid
from pathlib import Path

import apps.accounts.models
import apps.complaints.storage
from apps.complaints.storage import PrivateMediaStorage
from django.core.files.storage import FileSystemStorage
from django.db import migrations, models


def move_ids_to_private_storage(apps, schema_editor):
    """Same move as common.0005, for the multi-ID-type documents that used to
    sit at /media/verification_documents/<date>/<original filename>."""
    VerificationDocument = apps.get_model("accounts", "VerificationDocument")
    public = FileSystemStorage()  # MEDIA_ROOT
    private = PrivateMediaStorage()
    for doc in VerificationDocument.objects.all():
        old_name = doc.document_file.name
        if not old_name or not public.exists(old_name):
            continue
        new_name = f"verification_documents/{doc.user_id}/{uuid.uuid4().hex}{Path(old_name).suffix.lower()}"
        with public.open(old_name, "rb") as source:
            saved_name = private.save(new_name, source)
        VerificationDocument.objects.filter(pk=doc.pk).update(document_file=saved_name)
        public.delete(old_name)


class Migration(migrations.Migration):

    dependencies = [
        ('accounts', '0015_userprofile_blocked_until'),
    ]

    operations = [
        migrations.AlterField(
            model_name='verificationdocument',
            name='document_file',
            field=models.FileField(storage=apps.complaints.storage.PrivateMediaStorage(), upload_to=apps.accounts.models.id_document_path),
        ),
        # Not reversible: moving files back would re-expose them publicly.
        migrations.RunPython(move_ids_to_private_storage, migrations.RunPython.noop),
    ]
