import 'package:isar/isar.dart';

part 'app_user.g.dart';

@Collection()
class AppUser {
  Id id = Isar.autoIncrement;

  late String pinHash;
  late String role; // "owner" or "cashier"
  late String name;
}
