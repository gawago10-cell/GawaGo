/// Maps a raw job-application status to the same display label the web
/// app uses (frontend/src/utils/jobUtils.js: getApplicationStatusLabel),
/// so mobile and web show identical Applied/Hired/Rejected vocabulary.
String applicationStatusLabel(String status) {
  const labels = {
    'pending': 'Applied',
    'hire_requested': 'Hire Requested',
    'hired': 'Hired',
    'rejected': 'Rejected',
    'closed': 'Closed',
    // Displayed as Hired to avoid confusion with job completion.
    'completed': 'Hired',
  };
  final normalized = status.trim().toLowerCase();
  return labels[normalized] ?? formatStatus(status);
}

String formatStatus(String value) {
  final normalized = value.trim();
  if (normalized.isEmpty) return 'Unknown';
  return normalized
      .split(RegExp(r'[_\s-]+'))
      .where((part) => part.isNotEmpty)
      .map(
        (part) =>
            '${part.substring(0, 1).toUpperCase()}${part.substring(1).toLowerCase()}',
      )
      .join(' ');
}

String formatLocalDateTime(String value, {String fallback = 'Not available'}) {
  final normalized = value.trim();
  if (normalized.isEmpty) return fallback;
  final date = parseBackendDateTime(normalized);
  if (date == null) return normalized;
  final hour = date.hour % 12 == 0 ? 12 : date.hour % 12;
  final minute = date.minute.toString().padLeft(2, '0');
  final period = date.hour >= 12 ? 'PM' : 'AM';
  return '${_month(date.month)} ${date.day}, ${date.year} '
      '$hour:$minute $period';
}

String formatDateOrText(String value) {
  final normalized = value.trim();
  if (normalized.isEmpty) return 'Not specified';
  return DateTime.tryParse(normalized) == null
      ? normalized
      : formatLocalDateTime(normalized);
}

/// "3 hours ago" -- relative wording for a backend timestamp. Walks up the
/// unit ladder while the remaining amount still fills the next unit.
String formatTimeAgo(String value) {
  final date = parseBackendDateTime(value);
  if (date == null) return '';
  final seconds = DateTime.now().difference(date).inSeconds;
  if (seconds < 60) return 'just now';
  const units = [
    ('minute', 60),
    ('hour', 60),
    ('day', 24),
    ('month', 30),
    ('year', 12),
  ];
  var amount = seconds;
  var label = 'second';
  for (final (nextLabel, size) in units) {
    if (amount < size) break;
    amount = amount ~/ size;
    label = nextLabel;
  }
  return '$amount $label${amount == 1 ? '' : 's'} ago';
}

DateTime? parseBackendDateTime(String value) {
  final normalized = value.trim();
  if (normalized.isEmpty) return null;
  final hasTimezone = RegExp(
    r'(z|[+-]\d{2}:?\d{2})$',
    caseSensitive: false,
  ).hasMatch(normalized);
  final parseable = hasTimezone ? normalized : '${normalized}Z';
  return DateTime.tryParse(parseable)?.toLocal();
}

String _month(int value) => const [
  '',
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
][value];
