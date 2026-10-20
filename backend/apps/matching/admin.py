from django.contrib import admin

from apps.matching.models import RouteDistanceCache


@admin.register(RouteDistanceCache)
class RouteDistanceCacheAdmin(admin.ModelAdmin):
    list_display = ("job", "worker_profile", "distance_km", "updated_at")
    search_fields = ("job__title", "worker_profile__user__username")
    readonly_fields = ("created_at", "updated_at")
