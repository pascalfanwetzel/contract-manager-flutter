class AppRoutes {
  static const overview = '/';
  static const contracts = '/contracts';
  static const reminders = '/reminders';
  static const profile = '/profile';

  static const contractNew = '/contracts/new';
  static String contractDetails(String id) => '/contracts/$id';
}
