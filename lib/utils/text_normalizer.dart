String normalizeSpaces(String value) {
  return value.replaceAll(RegExp(r'\s+'), ' ').trim();
}

String normalizeSearch(String value) {
  return normalizeSpaces(value).toLowerCase();
}

String normalizePhoneForComparison(String value) {
  return normalizeSpaces(value)
      .replaceAll(RegExp(r'[\s\-\(\)]'), '')
      .trim();
}

String phoneDigitsOnly(String value) {
  return value.replaceAll(RegExp(r'\D'), '');
}

String normalizeColombianPhoneForSearch(String value) {
  final digits = phoneDigitsOnly(value);

  if (digits.startsWith('0057') && digits.length > 4) {
    return digits.substring(4);
  }

  if (digits.startsWith('57') && digits.length > 10) {
    return digits.substring(2);
  }

  return digits;
}

bool phoneMatchesIgnoringColombianCode({
  required String storedNumber,
  required String query,
}) {
  final storedDigits = phoneDigitsOnly(storedNumber);
  final queryDigits = phoneDigitsOnly(query);

  if (queryDigits.isEmpty) {
    return false;
  }

  final storedWithoutCode = normalizeColombianPhoneForSearch(storedNumber);
  final queryWithoutCode = normalizeColombianPhoneForSearch(query);

  return storedDigits.contains(queryDigits) ||
      storedWithoutCode.contains(queryDigits) ||
      storedDigits.contains(queryWithoutCode) ||
      storedWithoutCode.contains(queryWithoutCode);
}
