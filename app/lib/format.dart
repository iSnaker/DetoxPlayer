/// Russian plural form: 1 альбом, 2 альбома, 5 альбомов.
String plural(int n, String one, String few, String many) {
  final mod100 = n % 100;
  final mod10 = n % 10;
  if (mod100 >= 11 && mod100 <= 14) return '$n $many';
  if (mod10 == 1) return '$n $one';
  if (mod10 >= 2 && mod10 <= 4) return '$n $few';
  return '$n $many';
}

String tracksText(int n) => plural(n, 'трек', 'трека', 'треков');
String albumsText(int n) => plural(n, 'альбом', 'альбома', 'альбомов');

/// Playback time as M:SS, or H:MM:SS for an hour or more.
String clock(Duration d) {
  final total = d.inSeconds < 0 ? 0 : d.inSeconds;
  final h = total ~/ 3600;
  final m = (total % 3600) ~/ 60;
  final sec = (total % 60).toString().padLeft(2, '0');
  return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$sec' : '$m:$sec';
}
