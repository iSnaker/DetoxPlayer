import 'api/detox_api.dart';
import 'library/library.dart';
import 'player_controller.dart';

/// What every screen needs; created once per connection.
class Services {
  Services(this.api, this.library, this.player);

  final DetoxApi api;
  final Library library;
  final PlayerController player;
}
