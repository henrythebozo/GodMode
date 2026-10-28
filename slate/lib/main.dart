import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'data/demo_repository.dart';
import 'data/slate_repository.dart';
import 'data/supabase_repository.dart';
import 'screens/splash_screen.dart';
import 'state/app_state.dart';
import 'theme/app_theme.dart';

/// Pass these with --dart-define (or --dart-define-from-file=env.json) to use
/// a Supabase project. Without them the app runs on in-memory demo data.
const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const supabaseKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');

/// The app's URL scheme, registered in ios/Runner/Info.plist and
/// android/app/src/main/AndroidManifest.xml, for OAuth and email links.
const authRedirect = 'com.henrythebozo.slate://login-callback';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(CardApp(repository: await _createRepository()));
}

Future<SlateRepository> _createRepository() async {
  if (supabaseUrl.isEmpty || supabaseKey.isEmpty) return DemoRepository();
  await Supabase.initialize(url: supabaseUrl, publishableKey: supabaseKey);
  return SupabaseRepository(
    Supabase.instance.client,
    authRedirectUrl: kIsWeb ? null : authRedirect,
  );
}

class CardApp extends StatefulWidget {
  const CardApp({super.key, required this.repository});

  final SlateRepository repository;

  @override
  State<CardApp> createState() => _CardAppState();
}

class _CardAppState extends State<CardApp> {
  late final AppState _state = AppState(widget.repository);

  @override
  void dispose() {
    _state.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppScope(
      state: _state,
      child: MaterialApp(
        title: 'Slate',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        builder: _previewInsets,
        home: const SplashScreen(),
      ),
    );
  }
}

/// `--dart-define=PREVIEW_SAFE_AREA=62,34` fakes a phone's status bar and home
/// indicator insets in a browser, for comparing layouts against device
/// screenshots. Unset in normal builds.
const _previewSafeArea = String.fromEnvironment('PREVIEW_SAFE_AREA');

Widget _previewInsets(BuildContext context, Widget? child) {
  if (_previewSafeArea.isEmpty || child == null) return child ?? const SizedBox.shrink();
  final [top, bottom] = [for (final v in _previewSafeArea.split(',')) double.parse(v)];
  final insets = EdgeInsets.only(top: top, bottom: bottom);
  final media = MediaQuery.of(context);
  return MediaQuery(
    data: media.copyWith(padding: insets, viewPadding: insets),
    child: child,
  );
}
