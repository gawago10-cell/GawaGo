"""Deletes a model's own file(s) from storage when the file is replaced or
the row is deleted. Without this, every profile-photo swap, certificate
re-upload, and job-image delete left its old blob on disk forever (F19).
"""

from django.db.models.signals import post_delete, pre_save


def cleanup_files_on_change_and_delete(model, field_names):
    """Registers pre_save/post_delete handlers for `model` that delete the
    previous file from storage whenever one of `field_names` is replaced or
    the row itself is removed. Call once per model from AppConfig.ready()."""

    def _pre_save(sender, instance, **kwargs):
        if not instance.pk:
            return
        previous = sender.objects.filter(pk=instance.pk).first()
        if not previous:
            return
        for field_name in field_names:
            old_file = getattr(previous, field_name)
            new_file = getattr(instance, field_name)
            if old_file and old_file.name != getattr(new_file, "name", None):
                old_file.delete(save=False)

    def _post_delete(sender, instance, **kwargs):
        for field_name in field_names:
            file_ = getattr(instance, field_name)
            if file_:
                file_.delete(save=False)

    pre_save.connect(_pre_save, sender=model, weak=False)
    post_delete.connect(_post_delete, sender=model, weak=False)
