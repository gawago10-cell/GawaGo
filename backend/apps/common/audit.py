"""One call site for recording an admin action to the audit log, so every
admin-facing view logs it the same way instead of each hand-rolling the
actor/username-snapshot bookkeeping.
"""


def log_admin_action(actor, action, *, target_label="", target_type="", target_id=None, detail=""):
    from apps.common.models import AdminActionLog

    AdminActionLog.objects.create(
        actor=actor,
        actor_username=getattr(actor, "username", ""),
        action=action,
        target_label=target_label,
        target_type=target_type,
        target_id=target_id,
        detail=detail,
    )
