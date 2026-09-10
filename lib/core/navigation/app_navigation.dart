import 'package:flutter/material.dart';

/// Navigator, ki ga uporabljajo elementi, postavljeni izven Navigatorjevega
/// drevesa (npr. globalni mini player v `MaterialApp.builder`).
final appNavigatorKey = GlobalKey<NavigatorState>();
