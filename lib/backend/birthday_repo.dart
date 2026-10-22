import 'backend.dart';

class BirthdayRepo {
  static Future<bool> claimIfDue() async =>
      await db.rpc('claim_member_birthday_wish') as bool;
}
