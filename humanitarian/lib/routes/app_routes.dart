class AppRoutes {
  static const splash = '/splash';
  static const welcome = '/';
  static const authLogin = '/login';
  static const authRegister = '/register';
  static const authVerify = '/verify';
  // New-user onboarding: registration form + admin-approval waiting screen.
  // (Replaces the removed '/role-selection' choose-your-role screen.)
  static const registration = '/registration';
  static const pendingApproval = '/pending-approval';
  // Note #40 — guest account upgrade (phone + OTP, then the same
  // registration form as any new signup).
  static const guestUpgrade = '/guest-upgrade';
  static const home = '/home';
  static const donations = '/donations';
  static const donationDetails = '/donations/details';
  static const notifications = '/notifications';
}
