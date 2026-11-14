/// Small text helpers shared by screens.
library;

/// "just now", "42 s ago", "3 min ago" from a time in seconds since 1970.
String agoText(int? epochSeconds) {
  if (epochSeconds == null) return 'never';
  final seconds = DateTime.now().millisecondsSinceEpoch ~/ 1000 - epochSeconds;
  if (seconds < 5) return 'just now';
  if (seconds < 90) return '$seconds s ago';
  if (seconds < 5400) return '${seconds ~/ 60} min ago';
  return '${seconds ~/ 3600} h ago';
}

/// "09:12" from a time in seconds since 1970.
String clockText(int epochSeconds) {
  final time = DateTime.fromMillisecondsSinceEpoch(epochSeconds * 1000);
  return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
}

/// True when the time is on today's date.
bool isToday(int epochSeconds) {
  final time = DateTime.fromMillisecondsSinceEpoch(epochSeconds * 1000);
  final now = DateTime.now();
  return time.year == now.year && time.month == now.month && time.day == now.day;
}

/// "4:07" (minutes:seconds) since a time in seconds since 1970.
String elapsedText(int? epochSeconds) {
  if (epochSeconds == null) return '';
  final seconds = (DateTime.now().millisecondsSinceEpoch ~/ 1000 - epochSeconds).clamp(0, 359999);
  return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
}
