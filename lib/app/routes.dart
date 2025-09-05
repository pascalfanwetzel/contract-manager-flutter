class AppRoutes {
  static const overview = '/';
  static const contracts = '/contracts';
    static const profile = '/profile';
  static const welcome = '/welcome';
  static const unlock = '/unlock';

  static const contractNew = '/contracts/new';
  static String contractDetails(String id) => '/contracts/$id';

  // Profile subroutes
  static const profileUser = '/profile/user';
  static const profileSettings = '/profile/settings';
  static const profileNotifications = '/profile/notifications';
  static const profileStorage = '/profile/storage';
  static const profilePrivacy = '/profile/privacy';
  static const profileHelp = '/profile/help';
}
