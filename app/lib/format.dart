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
