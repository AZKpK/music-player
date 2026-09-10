import 'package:flutter/material.dart';

/// Navigator, ki ga uporabljajo elementi, postavljeni izven Navigatorjevega
/// drevesa (npr. globalni mini player v `MaterialApp.builder`).
final appNavigatorKey = GlobalKey<NavigatorState>();

/// Omogoča prikaz snackbarov (npr. napaka pri predvajanju, glej
/// `AudioPlayerHandler.playbackErrors`) od koderkoli v app-u, ne glede na to,
/// kateri zaslon je trenutno na vrhu Navigatorja.
final scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();
