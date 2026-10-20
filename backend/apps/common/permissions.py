from rest_framework.permissions import BasePermission, SAFE_METHODS


def is_platform_admin(user):
    return bool(user and user.is_authenticated and user.is_staff)


def is_platform_superadmin(user):
    return bool(user and user.is_authenticated and user.is_staff and user.is_superuser)


class IsPlatformAdmin(BasePermission):
    message = "Only platform admins can perform this action."

    def has_permission(self, request, view):
        return is_platform_admin(request.user)


class IsPlatformSuperAdmin(BasePermission):
    message = "Only platform superadmins can perform this action."

    def has_permission(self, request, view):
        return is_platform_superadmin(request.user)


class IsAdminOrReadOnly(BasePermission):
    def has_permission(self, request, view):
        if request.method in SAFE_METHODS:
            return True
        return is_platform_admin(request.user)


class IsOwnerOrAdmin(BasePermission):
    def has_object_permission(self, request, view, obj):
        if is_platform_admin(request.user):
            return True
        owner = getattr(obj, "user", None) or getattr(obj, "household", None) or getattr(obj, "recipient", None)
        return owner == request.user
