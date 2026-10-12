/// Bundled illustrations downloaded from the Stitch export
/// (see docs/asset-inventory.md).
abstract final class AppImages {
  static const pandaWelcome = 'assets/images/panda_welcome.jpg';
  static const pandaHoodie = 'assets/images/panda_hoodie.jpg';
  static const pandaMissions = 'assets/images/panda_missions.jpg';
  static const pandaDrawing = 'assets/images/panda_drawing.jpg';
  static const pandaCheering = 'assets/images/panda_cheering.jpg';
  static const parentAuthHero = 'assets/images/parent_auth_hero.jpg';
  static const gardenScene = 'assets/images/garden_scene.jpg';
  static const treasureChest = 'assets/images/treasure_chest.jpg';
}

/// The six avatars offered on "Create Child Profile". The key is what we
/// store on the device; the backend has no avatar-key field (B7).
enum ChildAvatarOption {
  explorer('assets/images/avatars/avatar_explorer.jpg'),
  braids('assets/images/avatars/avatar_braids.jpg'),
  cap('assets/images/avatars/avatar_cap.jpg'),
  hero('assets/images/avatars/avatar_hero.jpg'),
  scientist('assets/images/avatars/avatar_scientist.jpg'),
  astro('assets/images/avatars/avatar_astro.jpg');

  const ChildAvatarOption(this.asset);

  final String asset;

  static ChildAvatarOption? fromKey(String? key) {
    for (final option in values) {
      if (option.name == key) return option;
    }
    return null;
  }
}
