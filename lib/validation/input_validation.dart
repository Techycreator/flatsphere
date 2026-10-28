class InputValidation {
  static bool isEmail(String value) {
    final email = value.trim();
    return email.length <= 254 && RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email);
  }

  static bool isPhone(String value) {
    final phone = value.trim();
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    return digits.length >= 5 && digits.length <= 15 && RegExp(r'^[+0-9() -]+$').hasMatch(phone);
  }

  static bool isOptionalPhone(String value) => value.trim().isEmpty || isPhone(value);

  static bool isVehicleRegistration(String value) {
    final registration = value.trim().toUpperCase();
    final compact = registration.replaceAll(RegExp(r'[ \-/.]'), '');
    return compact.length >= 5 &&
        compact.length <= 15 &&
        RegExp(r'^[A-Z0-9]+$').hasMatch(compact) &&
        RegExp(r'\d').hasMatch(compact);
  }
}
