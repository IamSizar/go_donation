class AppRoutes {
  static const splash = '/splash';
  static const welcome = '/';
  static const authLogin = '/login';
  // '/register' was removed: the screen behind it performed no registration —
  // it waited 650ms and forwarded to '/verify' — and nothing ever navigated
  // to it. Real signup is the phone/OTP flow on '/login'.
  static const authVerify = '/verify';
  // A16 — the last step of sign-up: the code proved the number, this screen
  // turns that into the password every later sign-in uses. Also the way back in
  // for an account created before passwords existed.
  static const authCreatePassword = '/create-password';
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
