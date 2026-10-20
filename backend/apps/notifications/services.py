from django.conf import settings
from django.contrib.auth.models import User
from django.core.mail import send_mail
from django.db import transaction

from apps.common.background import enqueue
from apps.notifications.models import Notification


def send_notification_email(recipient: User, title: str, message: str) -> None:
    if not recipient.email:
        return

    body = (
        f"Hello {recipient.get_full_name().strip() or recipient.username},\n\n"
        f"{message}\n\n"
        "You can also view this notification in your GawaGo account."
    )
    send_mail(
        f"GawaGo: {title}",
        body,
        getattr(settings, "DEFAULT_FROM_EMAIL", None),
        [recipient.email],
        fail_silently=True,
    )


def create_notification(
    *,
    recipient: User,
    notification_type: str,
    title: str,
    message: str,
    actor: User | None = None,
    related_job_id: int | None = None,
    related_application_id: int | None = None,
    action_type: str = Notification.ACTION_NONE,
    action_url: str = "",
    requires_action: bool = False,
    send_email: bool = True,
) -> Notification:
    notification = Notification.objects.create(
        recipient=recipient,
        actor=actor,
        notification_type=notification_type,
        title=title,
        message=message,
        related_job_id=related_job_id,
        related_application_id=related_application_id,
        action_type=action_type or Notification.ACTION_NONE,
        action_url=action_url,
        requires_action=requires_action,
    )
    if send_email:
        send_notification_email(recipient, title, message)
    return notification


def notify_admins(*, title: str, message: str, superadmins_only: bool = False) -> int:
    """Admin alerts (AGENTS.md III.A): tell every active admin that something
    is waiting in a review queue. Complaints are only visible to superadmins,
    so alerts about them go to superadmins only.

    The rows are written now; the mirrored emails go out in the background
    once the request's transaction commits, so a slow mail provider never
    holds up the worker or household who triggered the alert."""
    admins = User.objects.filter(is_active=True, is_staff=True)
    if superadmins_only:
        admins = admins.filter(is_superuser=True)
    notification_ids = [
        create_notification(
            recipient=admin,
            notification_type=Notification.TYPE_ADMIN_ALERT,
            title=title,
            message=message,
            send_email=False,
        ).id
        for admin in admins
    ]
    if notification_ids:
        transaction.on_commit(lambda: enqueue(send_notification_emails, notification_ids))
    return len(notification_ids)


def send_notification_emails(notification_ids) -> None:
    """Background task: email the recipients of already-saved notifications."""
    for notification in Notification.objects.select_related("recipient").filter(id__in=notification_ids):
        send_notification_email(notification.recipient, notification.title, notification.message)
