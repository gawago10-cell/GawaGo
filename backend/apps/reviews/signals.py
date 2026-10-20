from django.contrib.auth import get_user_model
from django.db.models.signals import post_delete, post_save, pre_save
from django.dispatch import receiver

from apps.reviews.models import Review
from apps.reviews.services import recalculate_user_rating


@receiver(pre_save, sender=Review)
def remember_previous_review_target(sender, instance, **kwargs):
    if not instance.pk:
        instance._previous_target_id = None
        return

    previous = sender.objects.filter(pk=instance.pk).select_related("target").first()
    instance._previous_target_id = previous.target_id if previous else None


@receiver(post_save, sender=Review)
def update_worker_rating_after_save(sender, instance, **kwargs):
    previous_target_id = getattr(instance, "_previous_target_id", None)
    if previous_target_id and previous_target_id != instance.target_id:
        previous_target = get_user_model().objects.filter(pk=previous_target_id).first()
        if previous_target:
            recalculate_user_rating(previous_target)
    recalculate_user_rating(instance.target)


@receiver(post_delete, sender=Review)
def update_worker_rating_after_delete(sender, instance, **kwargs):
    recalculate_user_rating(instance.target)
