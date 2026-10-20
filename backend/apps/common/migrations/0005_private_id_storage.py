import uuid
from pathlib import Path

import apps.common.models
import apps.complaints.storage
from apps.complaints.storage import PrivateMediaStorage
from django.core.files.storage import FileSystemStorage
from django.db import migrations, models


def move_ids_to_private_storage(apps, schema_editor):
    """IDs used to live under MEDIA_ROOT at verification_documents/<user id>/
    <original filename>, downloadable by anyone via /media/. Move each file
    into private storage under a random name and delete the public copy."""
    VerificationRequest = apps.get_model("common", "VerificationRequest")
    public = FileSystemStorage()  # MEDIA_ROOT
    private = PrivateMediaStorage()
    for record in VerificationRequest.objects.all():
        updates = {}
        for field in ("primary_id_file", "secondary_doc_file"):
            old_name = getattr(record, field).name
            if not old_name or not public.exists(old_name):
                continue  # empty, already moved, or missing
            new_name = f"verification_documents/{record.worker_id}/{uuid.uuid4().hex}{Path(old_name).suffix.lower()}"
            with public.open(old_name, "rb") as source:
                updates[field] = private.save(new_name, source)
            public.delete(old_name)
        if updates:
            VerificationRequest.objects.filter(pk=record.pk).update(**updates)


class Migration(migrations.Migration):

    dependencies = [
        ('common', '0004_revokedtoken'),
    ]

    operations = [
        migrations.AlterField(
            model_name='verificationrequest',
            name='primary_id_file',
            field=models.FileField(blank=True, null=True, storage=apps.complaints.storage.PrivateMediaStorage(), upload_to=apps.common.models.verification_document_path),
        ),
        migrations.AlterField(
            model_name='verificationrequest',
            name='secondary_doc_file',
            field=models.FileField(blank=True, null=True, storage=apps.complaints.storage.PrivateMediaStorage(), upload_to=apps.common.models.verification_document_path),
        ),
        # Not reversible: moving files back would re-expose them publicly.
        migrations.RunPython(move_ids_to_private_storage, migrations.RunPython.noop),
    ]
