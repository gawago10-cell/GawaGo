from django import forms
from django.contrib import admin

from apps.accounts.serializers import MAX_WORKER_SKILLS, SKILL_NAME_MAX_LENGTH
from apps.accounts.services import ensure_portfolio_skills
from apps.accounts.models import (
    PasswordResetRequest,
    SignupVerificationRequest,
    UserProfile,
    WorkerAvailability,
)


class UserProfileAdminForm(forms.ModelForm):
    class Meta:
        model = UserProfile
        fields = "__all__"

    def clean_skills(self):
        """Same rules as the API: names normalised, no duplicates, at most 3,
        each short enough for the portfolio entry it gets."""
        skills = self.cleaned_data.get("skills") or []
        if not isinstance(skills, list):
            raise forms.ValidationError("Enter the skills as a list of names.")
        cleaned = []
        seen = set()
        for value in skills:
            name = " ".join(str(value).split())
            if not name or name.casefold() in seen:
                continue
            if len(name) > SKILL_NAME_MAX_LENGTH:
                raise forms.ValidationError(f"Skill names can be at most {SKILL_NAME_MAX_LENGTH} characters.")
            seen.add(name.casefold())
            cleaned.append(name)
        if len(cleaned) > MAX_WORKER_SKILLS:
            raise forms.ValidationError(f"Workers can list at most {MAX_WORKER_SKILLS} skills.")
        return cleaned


@admin.register(UserProfile)
class UserProfileAdmin(admin.ModelAdmin):
    form = UserProfileAdminForm
    list_display = ("user", "role", "verification_status", "rating_count", "average_rating")
    list_filter = ("role", "verification_status")
    search_fields = ("user__username", "user__email")

    def save_model(self, request, obj, form, change):
        super().save_model(request, obj, form, change)
        # The portfolio lists one entry per profile skill (what matching reads).
        if obj.role == UserProfile.ROLE_WORKER:
            ensure_portfolio_skills(obj.user, obj.skills)


@admin.register(WorkerAvailability)
class WorkerAvailabilityAdmin(admin.ModelAdmin):
    list_display = ("worker", "date", "start_time", "end_time", "is_available")
    list_filter = ("date", "is_available")
    search_fields = ("worker__username", "worker__email")


@admin.register(PasswordResetRequest)
class PasswordResetRequestAdmin(admin.ModelAdmin):
    list_display = ("user", "email", "created_at", "expires_at", "used_at", "attempts")
    search_fields = ("user__username", "email")


@admin.register(SignupVerificationRequest)
class SignupVerificationRequestAdmin(admin.ModelAdmin):
    list_display = ("user", "email", "created_at", "expires_at", "verified_at")
    search_fields = ("user__username", "email")
