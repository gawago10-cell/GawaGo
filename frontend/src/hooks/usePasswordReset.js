import { requestPasswordReset, resetPassword, verifyPasswordResetToken } from "../services/backendDataService";
import { isValidEmailAddress } from "../utils/locationServices";

export function usePasswordReset({
  forgotPasswordForm,
  setForgotPasswordError,
  setForgotPasswordForm,
  setForgotPasswordLoading,
  setForgotPasswordNotice,
  setForgotPasswordStep,
}) {
  function handleForgotPasswordChange(event) {
    const { name, value } = event.target;
    setForgotPasswordForm((prev) => ({
      ...prev,
      [name]: value,
    }));
  }

  async function handleForgotPasswordEmailSubmit(event) {
    event.preventDefault();
    const email = forgotPasswordForm.email.trim();
    if (!isValidEmailAddress(email)) {
      setForgotPasswordError("Please enter a valid email address.");
      return;
    }
    setForgotPasswordLoading(true);
    setForgotPasswordError("");
    setForgotPasswordNotice("");
    try {
      const data = await requestPasswordReset(email);
      setForgotPasswordStep("verify");
      setForgotPasswordNotice(data?.detail || "Reset code sent to your email.");
    } catch (error) {
      setForgotPasswordError(error.message || "Unable to send reset code.");
    } finally {
      setForgotPasswordLoading(false);
    }
  }

  async function handleVerifyResetToken(event) {
    event.preventDefault();
    const email = forgotPasswordForm.email.trim();
    const token = forgotPasswordForm.token.trim();
    if (!email || !token) {
      setForgotPasswordError("Please enter the email and reset code.");
      return;
    }
    setForgotPasswordLoading(true);
    setForgotPasswordError("");
    setForgotPasswordNotice("");
    try {
      const data = await verifyPasswordResetToken(email, token);
      setForgotPasswordStep("reset");
      setForgotPasswordNotice(data?.detail || "Code verified.");
    } catch (error) {
      setForgotPasswordError(error.message || "Invalid reset code.");
    } finally {
      setForgotPasswordLoading(false);
    }
  }

  async function handleResetPassword(event) {
    event.preventDefault();
    const { email, token, newPassword, confirmPassword } = forgotPasswordForm;
    if (!newPassword || newPassword.length < 8) {
      setForgotPasswordError("Password must be at least 8 characters.");
      return;
    }
    if (newPassword !== confirmPassword) {
      setForgotPasswordError("Passwords do not match.");
      return;
    }
    setForgotPasswordLoading(true);
    setForgotPasswordError("");
    setForgotPasswordNotice("");
    try {
      const data = await resetPassword({
        email: email.trim(),
        token: token.trim(),
        newPassword,
      });
      setForgotPasswordNotice(data?.detail || "Password reset successful.");
      setForgotPasswordStep("done");
    } catch (error) {
      setForgotPasswordError(error.message || "Unable to reset password.");
    } finally {
      setForgotPasswordLoading(false);
    }
  }

  return {
    handleForgotPasswordChange,
    handleForgotPasswordEmailSubmit,
    handleResetPassword,
    handleVerifyResetToken,
  };
}
