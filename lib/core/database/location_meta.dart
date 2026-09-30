// Shared constants for Phase 10 (home & household inventory): room
// templates for quick location creation and place name suggestions.

/// Common room/area templates offered as quick picks in the location form.
/// Users can always type a custom name instead.
abstract final class LocationTemplates {
  static const List<String> all = [
    'Living Room',
    'Bedroom',
    'Kitchen',
    'Bathroom',
    'Garage',
    'Basement',
    'Attic',
    'Closet',
    'Office',
    'Storage',
  ];
}

/// Suggested names when creating a new place.
abstract final class PlaceTemplates {
  static const List<String> all = [
    'My Home',
    'Parents\u2019 Home',
    'Apartment',
    'Garage',
    'Storage Unit',
    'Office',
    'Car',
  ];
}
