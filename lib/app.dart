import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'runtime/runtime_coordinator.dart';
import 'runtime/runtime_view.dart';
import 'runtime/capability.dart';
import 'theme/brand_theme.dart';
import 'runtime/feature_runtime.dart';

class ServerDeckApp extends StatelessWidget {
  const ServerDeckApp({
    super.key,
    required this.runtime,
    required this.store,
    this.features,
  });
  final RuntimeCoordinator runtime;
  final RuntimeStore store;
  final FeatureRuntime? Function()? features;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: runtime,
    builder: (context, _) => MaterialApp(
      title: 'ServerDeck',
      debugShowCheckedModeBanner: false,
      theme: BrandTheme.light,
      darkTheme: BrandTheme.dark,
      themeMode: store.theme == 'light' ? ThemeMode.light : ThemeMode.dark,
      locale: const Locale('ru'),
      supportedLocales: const [Locale('ru')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: RuntimeView(runtime: runtime, features: features?.call()),
    ),
  );
}
