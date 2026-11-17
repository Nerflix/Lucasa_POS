import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'data/database/app_database.dart';
import 'services/supabase_service.dart';
import 'services/connectivity_service.dart';
import 'services/sync_service.dart';
import 'services/auth_service.dart';
import 'services/time_service.dart';
import 'core/config/supabase_config.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/login_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load environment variables from .env file
  await dotenv.load(fileName: ".env");

  // Set system navigation bar color to white
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      systemNavigationBarColor: Colors.white,
      systemNavigationBarIconBrightness: Brightness.dark,
      systemNavigationBarDividerColor: Colors.white, // Remove divider line
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ),
  );

  // Set edge-to-edge mode (immersive)
  SystemChrome.setEnabledSystemUIMode(
    SystemUiMode.edgeToEdge,
  );

  // Initialize Supabase
  final supabaseService = SupabaseService.instance;
  await supabaseService.initialize();

  // Initialize local database
  final database = AppDatabase();

  // Initialize connectivity service
  final connectivityService = ConnectivityService.instance;
  
  // Initialize time service (gets real time from internet)
  final timeService = TimeService();
  
  // Initialize sync service
  final syncService = SyncService.initialize(
    database,
    supabaseService,
    connectivityService,
    timeService,
  );
  
  // Initialize auth service
  final authService = AuthService(database, supabaseService);
  
  // Create storage buckets if they don't exist
  try {
    await supabaseService.createBucketIfNotExists(SupabaseConfig.configBucketName);
    await supabaseService.createBucketIfNotExists(SupabaseConfig.receiptsBucketName);
  } catch (e) {
    print('Error creating buckets: $e');
  }
  
  runApp(
    MultiProvider(
      providers: [
        Provider<AppDatabase>.value(value: database),
        Provider<SupabaseService>.value(value: supabaseService),
        Provider<ConnectivityService>.value(value: connectivityService),
        Provider<TimeService>.value(value: timeService),
        ChangeNotifierProvider<SyncService>.value(value: syncService),
        ChangeNotifierProvider<AuthService>.value(value: authService),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Set navigation bar color every time the app builds
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        systemNavigationBarColor: Color(0xFFFFFFFF), // Pure white
        systemNavigationBarIconBrightness: Brightness.dark,
        systemNavigationBarDividerColor: Color(0xFFFFFFFF), // Pure white
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
      ),
    );
    
    return MaterialApp(
      title: 'Lucasa POS',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme.copyWith(
        scaffoldBackgroundColor: Colors.white,
      ),
      home: const LoginPage(),
    );
  }
}

