import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive/hive.dart';
import 'package:palette_generator/palette_generator.dart';
import '/utils/helper.dart';

/// Cor de destaque única e consistente do app (estilo "Spotify Green").
/// Troque por `Color(0xFF2D9CFF)` se preferir a variante "azul elétrico".
const Color kAccentColor = Color(0xFF1DB954);

/// Fundo profundo (grafite/preto) usado no tema premium — evita o efeito
/// "lavado" do cinza-médio padrão do Material.
const Color kDeepBackground = Color(0xFF0A0A0A);

/// Superfície ligeiramente mais clara que o fundo, para cards, bottom
/// sheets e a própria NavigationBar — cria profundidade sem virar um
/// "bloco" visualmente destacado.
const Color kSurfaceElevated = Color(0xFF181818);

/// Vermelho de destaque estilo Apple Music (mesmo tom usado nos ícones
/// de "play"/highlights do app da Apple). Usado só no ThemeType.light,
/// que agora é o padrão do redesign "elegante, minimalista".
const Color kAppleAccentColor = Color(0xFFFA233B);

/// Fundo "agrupado" do iOS (systemGroupedBackground) — cinza bem claro
/// atrás de cards brancos, em vez de branco puro colado em branco puro.
/// É o que dá aquela sensação de hierarquia/respiro do Apple Music.
const Color kAppleGroupedBackground = Color(0xFFF2F2F7);

class ThemeController extends GetxController {
  final primaryColor = Colors.deepPurple[400].obs;
  final textColor = Colors.white24.obs;
  final themedata = Rxn<ThemeData>();

  /// The method channel for setting the title bar color on Windows.
  final platform = const MethodChannel('win_titlebar_color');
  String? currentSongId;
  late Brightness systemBrightness;

  ThemeController() {
    systemBrightness =
        WidgetsBinding.instance.platformDispatcher.platformBrightness;

    primaryColor.value =
        Color(Hive.box('appPrefs').get("themePrimaryColor") ?? 4278199603);

    changeThemeModeType(ThemeType.values[
        // Redesign "estilo Apple Music": tema claro fixo passou a ser o
        // padrão do app (era ThemeType.dynamic = índice 0). Quem já
        // tinha escolhido outro tema manualmente nas Configurações não
        // é afetado — esse fallback só vale pra instalação nova/limpa.
        Hive.box('appPrefs').get("themeModeType") ?? ThemeType.light.index]);

    _listenSystemBrightness();

    super.onInit();
  }

  void _listenSystemBrightness() {
    final platformDispatcher = WidgetsBinding.instance.platformDispatcher;
    platformDispatcher.onPlatformBrightnessChanged = () {
      systemBrightness = platformDispatcher.platformBrightness;
      changeThemeModeType(
          ThemeType.values[Hive.box('appPrefs').get("themeModeType")],
          sysCall: true);
    };
  }

  void changeThemeModeType(dynamic value, {bool sysCall = false}) {
    if (value == ThemeType.system) {
      themedata.value = _createThemeData(
          null,
          systemBrightness == Brightness.light
              ? ThemeType.light
              : ThemeType.dark);
    } else {
      if (sysCall) return;
      themedata.value = _createThemeData(
          value == ThemeType.dynamic
              ? _createMaterialColor(primaryColor.value!)
              : null,
          value);
    }
    setWindowsTitleBarColor(themedata.value!.scaffoldBackgroundColor);
  }

  void setTheme(ImageProvider imageProvider, String songId) async {
    if (songId == currentSongId) return;
    PaletteGenerator generator = await PaletteGenerator.fromImageProvider(
        ResizeImage(imageProvider, height: 200, width: 200));
    //final colorList = generator.colors;
    final paletteColor = generator.dominantColor ??
        generator.darkMutedColor ??
        generator.darkVibrantColor ??
        generator.lightMutedColor ??
        generator.lightVibrantColor;
    primaryColor.value = paletteColor!.color;
    textColor.value = paletteColor.bodyTextColor;
    // printINFO(paletteColor.color.computeLuminance().toString());0.11 ref
    if (paletteColor.color.computeLuminance() > 0.10) {
      primaryColor.value = paletteColor.color.withLightness(0.10);
      textColor.value = Colors.white54;
    }
    final primarySwatch = _createMaterialColor(primaryColor.value!);
    themedata.value = _createThemeData(primarySwatch, ThemeType.dynamic,
        textColor: textColor.value,
        titleColorSwatch: _createMaterialColor(textColor.value));
    currentSongId = songId;
    Hive.box('appPrefs').put("themePrimaryColor", (primaryColor.value!).value);
    setWindowsTitleBarColor(themedata.value!.scaffoldBackgroundColor);
  }

  ThemeData _createThemeData(MaterialColor? primarySwatch, ThemeType themeType,
      {MaterialColor? titleColorSwatch, Color? textColor}) {
    if (themeType == ThemeType.dynamic) {
      SystemChrome.setSystemUIOverlayStyle(
        SystemUiOverlayStyle(
            statusBarIconBrightness: Brightness.light,
            statusBarColor: Colors.transparent,
            systemNavigationBarColor: Colors.white.withOpacity(0.002),
            systemNavigationBarDividerColor: Colors.transparent,
            systemNavigationBarIconBrightness: Brightness.light,
            systemStatusBarContrastEnforced: false,
            systemNavigationBarContrastEnforced: true),
      );

      final baseTheme = ThemeData(
          useMaterial3: false,
          primaryColor: primarySwatch![500],
          colorScheme: ColorScheme.fromSwatch(
              accentColor: primarySwatch[200],
              brightness: Brightness.dark,
              backgroundColor: primarySwatch[700],
              primarySwatch: primarySwatch),
          //accentColor: primarySwatch[200],
          dialogBackgroundColor: primarySwatch[700],
          cardColor: primarySwatch[600],
          primaryColorLight: primarySwatch[400],
          primaryColorDark: primarySwatch[700],
          //secondaryHeaderColor: primarySwatch[50],
          canvasColor: primarySwatch[700],
          //scaffoldBackgroundColor: primarySwatch[700],
          bottomSheetTheme: BottomSheetThemeData(
              backgroundColor: primarySwatch[600],
              modalBarrierColor: primarySwatch[400]),
          textTheme: TextTheme(
            // fontSize maior + peso 800 + letterSpacing negativo: aproxima
            // o header ("Boa noite") do tracking apertado e geométrico da
            // Spotify Circular/Gotham.
            titleLarge: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.6,
                color: Colors.white),
            titleMedium: const TextStyle(
                fontWeight: FontWeight.bold, color: Colors.white),
            titleSmall: TextStyle(color: primarySwatch[100]),
            bodyMedium: TextStyle(color: primarySwatch[100]),
            labelMedium: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 23,
                color: textColor ?? primarySwatch[50]),
            labelSmall: TextStyle(
                fontSize: 15,
                color: titleColorSwatch != null
                    ? titleColorSwatch[900]
                    : primarySwatch[100],
                letterSpacing: 0,
                fontWeight: FontWeight.bold),
          ),
          indicatorColor: Colors.white,
          progressIndicatorTheme: ProgressIndicatorThemeData(
              linearTrackColor: (primarySwatch[300])!.computeLuminance() > 0.3
                  ? Colors.black54
                  : Colors.white70,
              color: textColor),
          navigationRailTheme: NavigationRailThemeData(
              backgroundColor: primarySwatch[700],
              selectedIconTheme: const IconThemeData(color: Colors.white),
              unselectedIconTheme: IconThemeData(color: primarySwatch[100]),
              selectedLabelTextStyle: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 15),
              unselectedLabelTextStyle: TextStyle(
                  color: primarySwatch[100], fontWeight: FontWeight.bold)),
          sliderTheme: SliderThemeData(
            inactiveTrackColor: primarySwatch[300],
            activeTrackColor: textColor,
            valueIndicatorColor: primarySwatch[400],
            thumbColor: Colors.white,
          ),
          textSelectionTheme: TextSelectionThemeData(
              cursorColor: primarySwatch[200],
              selectionColor: primarySwatch[200],
              selectionHandleColor: primarySwatch[200])
          //scaffoldBackgroundColor: primarySwatch[700]
          );
      return baseTheme.copyWith(
          textTheme: GoogleFonts.robotoTextTheme(baseTheme.textTheme));
    } else if (themeType == ThemeType.dark) {
      SystemChrome.setSystemUIOverlayStyle(
        SystemUiOverlayStyle(
            statusBarIconBrightness: Brightness.light,
            statusBarColor: Colors.transparent,
            systemNavigationBarColor: Colors.white.withOpacity(0.002),
            systemNavigationBarDividerColor: Colors.transparent,
            systemNavigationBarIconBrightness: Brightness.light,
            systemStatusBarContrastEnforced: false,
            systemNavigationBarContrastEnforced: true),
      );
      final baseTheme = ThemeData(
          useMaterial3: false,
          brightness: Brightness.dark,
          scaffoldBackgroundColor: kDeepBackground,
          canvasColor: kDeepBackground,
          primaryColor: kDeepBackground,
          primaryColorDark: Colors.black,
          primaryColorLight: kSurfaceElevated,
          cardColor: kSurfaceElevated,
          dialogBackgroundColor: kSurfaceElevated,
          colorScheme: ColorScheme.fromSeed(
            seedColor: kAccentColor,
            brightness: Brightness.dark,
            primary: kAccentColor,
            secondary: kAccentColor,
            surface: kSurfaceElevated,
            surfaceTint: Colors.transparent,
          ),
          progressIndicatorTheme: ProgressIndicatorThemeData(
              color: kAccentColor, linearTrackColor: Colors.white24),
          textTheme: const TextTheme(
              titleLarge: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.6,
                color: Colors.white,
              ),
              titleMedium: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
              titleSmall: TextStyle(color: Colors.white),
              labelMedium: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 23,
                color: Colors.white,
              ),
              labelSmall: TextStyle(
                  fontSize: 15,
                  letterSpacing: 0,
                  fontWeight: FontWeight.bold,
                  color: Colors.white),
              // Colors.grey puro tem baixo contraste sobre preto profundo;
              // white70 mantém legibilidade "premium" em textos secundários.
              bodyMedium: TextStyle(color: Colors.white70)),
          navigationRailTheme: NavigationRailThemeData(
              backgroundColor: kDeepBackground,
              indicatorColor: kAccentColor.withOpacity(0.18),
              indicatorShape: const StadiumBorder(),
              selectedIconTheme: const IconThemeData(
                color: kAccentColor,
              ),
              unselectedIconTheme: const IconThemeData(color: Colors.white38),
              selectedLabelTextStyle: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 15),
              unselectedLabelTextStyle: const TextStyle(
                  color: Colors.white38, fontWeight: FontWeight.bold)),
          // NavigationBar (Material 3) usada dentro do wrapper flutuante e
          // translúcido de bottom_nav_bar.dart. backgroundColor TRANSPARENT
          // é essencial aqui: é o BackdropFilter + Container translúcido do
          // widget que criam o efeito "vidro fosco" — se a NavigationBar
          // tivesse cor sólida, o blur ficaria escondido atrás dela.
          // Ícones (22) e labels (11) reduzidos e mais próximos = visual
          // "refinado" em vez do NavigationBar padrão, que é maior/espaçado.
          navigationBarTheme: NavigationBarThemeData(
            backgroundColor: Colors.transparent,
            surfaceTintColor: Colors.transparent,
            shadowColor: Colors.transparent,
            elevation: 0,
            height: 52,
            labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
            indicatorColor: kAccentColor.withOpacity(0.22),
            indicatorShape: const StadiumBorder(),
            iconTheme: WidgetStateProperty.resolveWith((states) {
              return IconThemeData(
                size: 22,
                color: states.contains(WidgetState.selected)
                    ? kAccentColor
                    : Colors.white60,
              );
            }),
            labelTextStyle: WidgetStateProperty.resolveWith((states) {
              return TextStyle(
                fontSize: 11,
                fontWeight: states.contains(WidgetState.selected)
                    ? FontWeight.w700
                    : FontWeight.w500,
                color: states.contains(WidgetState.selected)
                    ? kAccentColor
                    : Colors.white60,
              );
            }),
          ),
          bottomSheetTheme: const BottomSheetThemeData(
              backgroundColor: kSurfaceElevated,
              modalBarrierColor: Colors.black54),
          sliderTheme: const SliderThemeData(
            //base bar color
            inactiveTrackColor: Colors.white24,
            //buffered progress
            activeTrackColor: kAccentColor,
            //progress bar color
            valueIndicatorColor: kSurfaceElevated,
            thumbColor: kAccentColor,
          ),
          textSelectionTheme: const TextSelectionThemeData(
              cursorColor: kAccentColor,
              selectionColor: kAccentColor,
              selectionHandleColor: kAccentColor),
          inputDecorationTheme: const InputDecorationTheme(
              focusColor: kAccentColor,
              focusedBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: kAccentColor))));
      return baseTheme.copyWith(
          textTheme: GoogleFonts.robotoTextTheme(baseTheme.textTheme));
    } else {
      SystemChrome.setSystemUIOverlayStyle(
        SystemUiOverlayStyle(
            statusBarIconBrightness: Brightness.dark,
            statusBarColor: Colors.transparent,
            systemNavigationBarColor: Colors.white.withOpacity(0.002),
            systemNavigationBarDividerColor: Colors.transparent,
            systemNavigationBarIconBrightness: Brightness.dark,
            systemStatusBarContrastEnforced: false,
            systemNavigationBarContrastEnforced: false),
      );
      final baseTheme = ThemeData(
          useMaterial3: false,
          brightness: Brightness.light,
          // Fundo "agrupado" cinza-claro (não branco puro) atrás de
          // cards brancos — é o que dá a sensação de hierarquia e
          // "respiro" do Apple Music/Library (ver kAppleGroupedBackground).
          scaffoldBackgroundColor: kAppleGroupedBackground,
          canvasColor: kAppleGroupedBackground,
          cardColor: Colors.white,
          colorScheme: ColorScheme.fromSwatch(
              accentColor: kAppleAccentColor,
              backgroundColor: kAppleGroupedBackground,
              cardColor: Colors.white,
              brightness: Brightness.light),
          primaryColor: Colors.white,
          primaryColorLight: Colors.grey[300],
          progressIndicatorTheme: ProgressIndicatorThemeData(
              linearTrackColor: Colors.grey[300], color: kAppleAccentColor),
          textTheme: TextTheme(
              titleLarge: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.6,
                color: Colors.black,
              ),
              titleMedium: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.black,
              ),
              titleSmall: TextStyle(color: Colors.grey[600]),
              labelMedium: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 23,
                color: Colors.black,
              ),
              labelSmall: const TextStyle(
                  fontSize: 15,
                  letterSpacing: 0,
                  fontWeight: FontWeight.bold,
                  color: Colors.black),
              bodyMedium: TextStyle(color: Colors.grey[700])),
          navigationRailTheme: NavigationRailThemeData(
              backgroundColor: Colors.white,
              selectedIconTheme: const IconThemeData(color: kAppleAccentColor),
              unselectedIconTheme: IconThemeData(color: Colors.grey[500]),
              selectedLabelTextStyle: const TextStyle(
                  color: kAppleAccentColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 15),
              unselectedLabelTextStyle: TextStyle(
                  color: Colors.grey[500], fontWeight: FontWeight.bold)),
          bottomSheetTheme: BottomSheetThemeData(
              backgroundColor: Colors.white,
              modalBarrierColor: Colors.black.withOpacity(0.35),
              shape: const RoundedRectangleBorder(
                  borderRadius:
                      BorderRadius.vertical(top: Radius.circular(20)))),
          sliderTheme: const SliderThemeData(
            //base bar color
            inactiveTrackColor: Color(0xFFE5E5EA),
            //buffered progress
            activeTrackColor: kAppleAccentColor,
            //progress bar color
            valueIndicatorColor: Colors.white38,
            thumbColor: kAppleAccentColor,
            trackHeight: 3,
          ),
          textSelectionTheme: const TextSelectionThemeData(
              cursorColor: kAppleAccentColor,
              selectionColor: kAppleAccentColor,
              selectionHandleColor: kAppleAccentColor),
          // CORREÇÃO:
          dialogTheme: const DialogTheme(
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.all(Radius.circular(16)))),
          inputDecorationTheme: const InputDecorationTheme(
              focusColor: Colors.black,
              focusedBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: Colors.black))));
      return baseTheme.copyWith(
          textTheme: GoogleFonts.robotoTextTheme(baseTheme.textTheme));
    }
  }

  MaterialColor _createMaterialColor(Color color) {
    List strengths = <double>[.05];
    Map<int, Color> swatch = {};
    final int r = color.red, g = color.green, b = color.blue;

    for (int i = 1; i < 10; i++) {
      strengths.add(0.1 * i);
    }
    for (var strength in strengths) {
      final double ds = 0.5 - strength;
      swatch[(strength * 1000).round()] = Color.fromRGBO(
        r + ((ds < 0 ? r : (255 - r)) * ds).round(),
        g + ((ds < 0 ? g : (255 - g)) * ds).round(),
        b + ((ds < 0 ? b : (255 - b)) * ds).round(),
        1,
      );
    }
    return MaterialColor(color.value, swatch);
  }

  Future<void> setWindowsTitleBarColor(Color color) async {
    if (!GetPlatform.isWindows) return;
    try {
      Future.delayed(
          const Duration(milliseconds: 350),
          () async => await platform.invokeMethod('setTitleBarColor', {
                'r': color.red,
                'g': color.green,
                'b': color.blue,
              }));
    } on PlatformException catch (e) {
      printERROR("Failed to set title bar color: ${e.message}");
    }
  }
}

extension ComplementaryColor on Color {
  Color get complementaryColor => getComplementaryColor(this);
  Color getComplementaryColor(Color color) {
    int r = 255 - color.red;
    int g = 255 - color.green;
    int b = 255 - color.blue;
    return Color.fromARGB(color.alpha, r, g, b);
  }
}

extension ColorWithHSL on Color {
  HSLColor get hsl => HSLColor.fromColor(this);

  Color withSaturation(double saturation) {
    return hsl.withSaturation(clampDouble(saturation, 0.0, 1.0)).toColor();
  }

  Color withLightness(double lightness) {
    return hsl.withLightness(clampDouble(lightness, 0.0, 1.0)).toColor();
  }

  Color withHue(double hue) {
    return hsl.withHue(clampDouble(hue, 0.0, 360.0)).toColor();
  }
}

extension HexColor on Color {
  /// String is in the format "aabbcc" or "ffaabbcc" with an optional leading "#".
  static Color fromHex(String hexString) {
    final buffer = StringBuffer();
    if (hexString.length == 6 || hexString.length == 7) buffer.write('ff');
    buffer.write(hexString.replaceFirst('#', ''));
    return Color(int.parse(buffer.toString(), radix: 16));
  }

  /// Prefixes a hash sign if [leadingHashSign] is set to `true` (default is `true`).
  String toHex({bool leadingHashSign = true}) => '${leadingHashSign ? '#' : ''}'
      '${alpha.toRadixString(16).padLeft(2, '0')}'
      '${red.toRadixString(16).padLeft(2, '0')}'
      '${green.toRadixString(16).padLeft(2, '0')}'
      '${blue.toRadixString(16).padLeft(2, '0')}';
}

enum ThemeType {
  dynamic,
  system,
  dark,
  light,
}
