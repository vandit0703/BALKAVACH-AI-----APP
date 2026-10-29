import 'package:flutter/material.dart';

import 'video_feed_screen.dart';

/// Home is the child Shorts experience. The shell supplies the branded header,
/// Parent Gate, and bottom navigation around this full-height feed.
class WatchHomeScreen extends StatelessWidget {
  const WatchHomeScreen({super.key});

  @override
  Widget build(BuildContext context) =>
      const ShortsFeed(showMissionsAction: true);
}
