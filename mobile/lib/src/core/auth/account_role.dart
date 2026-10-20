/// The four account roles, mirroring the web app's getUserRole()
/// (frontend/src/utils/roles.js). The backend's login response carries
/// the account role ("superadmin", "admin", "household", "worker"); staff
/// admins arrive as "admin". Anything else is unknown -- it must never fall
/// through to the worker screens.
enum AccountRole { superadmin, admin, household, worker }

AccountRole? accountRoleFrom(String? value) {
  switch (value?.trim().toLowerCase()) {
    case 'superadmin':
      return AccountRole.superadmin;
    case 'admin':
      return AccountRole.admin;
    case 'household':
      return AccountRole.household;
    case 'worker':
      return AccountRole.worker;
    default:
      return null;
  }
}
