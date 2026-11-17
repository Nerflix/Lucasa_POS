class ValidationUtils {
  static String? validatePhone(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Phone number is required';
    }
    final phoneDigits = value.replaceAll(RegExp(r'[^0-9]'), '');
    if (phoneDigits.length != 10) {
      return 'Phone number must be 10 digits';
    }
    return null;
  }

  static String? validateEmail(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Email is required';
    }
    final emailRegex = RegExp(r'^[a-zA-Z0-9.]+@[a-zA-Z0-9]+\.[a-zA-Z]+');
    if (!emailRegex.hasMatch(value)) {
      return 'Please enter a valid email address (e.g., user@domain.com)';
    }
    return null;
  }
}
