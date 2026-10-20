from django.urls import path

from apps.accounts.views import (
    AdminAccountDetailView,
    AdminAccountListCreateView,
    ForgotPasswordRequestView,
    LoginView,
    LogoutView,
    MeProfileView,
    RegisterView,
    ResetPasswordView,
    UserAccountBlockAdminView,
    UserProfileListView,
    VerifyResetTokenView,
    VerifySignupView,
    WorkerAvailabilityView,
    WorkerPortfolioView,
    WorkerSkillView,
    WorkerCertificationView,
    WorkerCertificationFileView,
    WorkerPortfolioItemView,
    SkillRatingView,
    CertificateVerificationAdminView,
)


urlpatterns = [
    path("me/", MeProfileView.as_view(), name="profile-me"),
    path("me/availability/", WorkerAvailabilityView.as_view(), name="worker-availability"),
    path("me/portfolio/", WorkerPortfolioView.as_view(), name="worker-portfolio"),
    path("me/portfolio/skills/", WorkerSkillView.as_view(), name="worker-skill"),
    path("me/portfolio/skills/<int:skill_id>/", WorkerSkillView.as_view(), name="worker-skill-detail"),
    path("me/portfolio/certifications/", WorkerCertificationView.as_view(), name="worker-certification"),
    path("me/portfolio/certifications/<int:cert_id>/", WorkerCertificationView.as_view(), name="worker-certification-detail"),
    path("portfolio/certifications/<int:cert_id>/file/", WorkerCertificationFileView.as_view(), name="worker-certification-file"),
    path("me/portfolio/items/", WorkerPortfolioItemView.as_view(), name="worker-portfolio-item"),
    path("me/portfolio/items/<int:item_id>/", WorkerPortfolioItemView.as_view(), name="worker-portfolio-item-detail"),
    path("profiles/", UserProfileListView.as_view(), name="profile-list"),
    path("profiles/<int:user_id>/portfolio/", WorkerPortfolioView.as_view(), name="worker-portfolio-public"),
    path("profiles/<str:username>/block/", UserAccountBlockAdminView.as_view(), name="profile-block-admin"),
    path("register/", RegisterView.as_view(), name="register"),
    path("login/", LoginView.as_view(), name="login"),
    path("logout/", LogoutView.as_view(), name="logout"),
    path("verify-signup/", VerifySignupView.as_view(), name="verify-signup"),
    path("forgot-password/", ForgotPasswordRequestView.as_view(), name="forgot-password"),
    path("verify-reset-token/", VerifyResetTokenView.as_view(), name="verify-reset-token"),
    path("reset-password/", ResetPasswordView.as_view(), name="reset-password"),
]

# Skill rating endpoints (for reviewing jobs)
urlpatterns += [
    path("jobs/<int:job_id>/skill-ratings/", SkillRatingView.as_view(), name="skill-rating"),
]

# Admin certificate verification endpoints
urlpatterns += [
    path("admin/certificates/", CertificateVerificationAdminView.as_view(), name="certificate-admin-list"),
    path("admin/certificates/<int:cert_id>/", CertificateVerificationAdminView.as_view(), name="certificate-admin-verify"),
]

# Superadmin "Admin Management" endpoints
urlpatterns += [
    path("admin/admins/", AdminAccountListCreateView.as_view(), name="admin-account-list"),
    path("admin/admins/<str:username>/", AdminAccountDetailView.as_view(), name="admin-account-detail"),
]

# Verification document endpoints
urlpatterns += [
]
