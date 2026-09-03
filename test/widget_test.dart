import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart' show LatLng;

import 'package:ride/core/app_theme.dart';
import 'package:ride/core/busqueda_config.dart';
import 'package:ride/core/theme_controller.dart';
import 'package:ride/models/app_user.dart';
import 'package:ride/models/fleet.dart';
import 'package:ride/services/geocoding_service.dart';
import 'package:ride/services/h3_service.dart';
import 'package:ride/services/ride_service.dart';
import 'package:ride/services/map_style_service.dart';
import 'package:ride/services/places_service.dart';
import 'package:ride/services/routing_service.dart';
import 'package:ride/widgets/ride_map.dart';
import 'package:ride/models/trip.dart';
import 'package:ride/models/fare.dart';
import 'package:ride/models/support_ticket.dart';
import 'package:ride/models/user_role.dart';
import 'package:ride/models/vehicle_category.dart';
import 'package:ride/models/vehicle.dart';
import 'package:ride/screens/auth/auth_screen.dart';
import 'package:ride/screens/home/welcome_home_screen.dart';
import 'package:ride/screens/home/account_sheet.dart';
import 'package:ride/services/auth_service.dart';
import 'package:ride/widgets/auth_shell.dart';
import 'package:ride/widgets/panel_switcher.dart';

/// Pruebas de la app tras conectar Supabase.
///
/// La versión anterior de este archivo probaba el login, el registro y la
/// visibilidad por rol contra el almacén de cuentas en memoria que tenía
/// `AuthService` (`pasajero@ride.app` / `Ride1234` y las credenciales del
/// equipo leídas con `--dart-define`). Ese almacén ya no existe: ahora todo
/// pasa por Supabase Auth.
///
/// Esos casos no se pueden reescribir aquí sin salir a la red y sin crear
/// usuarios reales en el proyecto de producción, así que se retiraron en vez
/// de dejarlos fallando o marcados como omitidos. Para recuperarlos hace falta
/// un proyecto Supabase de pruebas con cuentas semilla y correrlos como
/// prueba de integración, no como prueba unitaria.
///
/// Lo que queda cubierto aquí es lo que sí se puede verificar sin red: el
/// árbol de widgets de la pantalla de autenticación y la lógica pura de los
/// modelos.
void main() {
  group('Pantalla de autenticación', () {
    /// Monta solo la pantalla de autenticación.
    ///
    /// No se usa [RideApp] porque su primera pantalla conecta con Supabase, y
    /// estas pruebas corren sin red. Lo que se verifica aquí es el árbol de
    /// widgets, que no depende de la sesión.
    Widget appDePrueba() =>
        MaterialApp(theme: AppTheme.light, home: const AuthScreen());

    /// Lleva la pantalla desde la bienvenida hasta [step].
    Future<void> abrir(WidgetTester tester, AuthStep step) async {
      await tester.pumpWidget(appDePrueba());
      await tester.pumpAndSettle();

      await tester.tap(
        find.text(
          step == AuthStep.login ? 'Ya tengo una cuenta' : 'Crear cuenta',
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('La bienvenida ofrece registro e inicio de sesión', (
      tester,
    ) async {
      await tester.pumpWidget(appDePrueba());
      await tester.pumpAndSettle();

      expect(find.text('BIENVENIDO A RIDE'), findsOneWidget);
      expect(find.text('Crear cuenta'), findsOneWidget);
      expect(find.text('Ya tengo una cuenta'), findsOneWidget);
    });

    testWidgets('El panel de marca solo aparece en pantallas anchas', (
      tester,
    ) async {
      // En móvil (800 px de ancho por defecto) la columna oscura se oculta,
      // igual que el `@media(max-width:850px)` de WEB-RIDE.
      await tester.pumpWidget(appDePrueba());
      await tester.pumpAndSettle();
      expect(find.byType(BrandPanel), findsNothing);

      tester.view.physicalSize = const Size(1280, 820);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(appDePrueba());
      await tester.pumpAndSettle();
      expect(find.byType(BrandPanel), findsOneWidget);

      // El formulario sigue funcionando junto al panel de marca.
      await tester.tap(find.text('Crear cuenta'));
      await tester.pumpAndSettle();
      expect(find.text('Comienza con Ride'), findsOneWidget);
    });

    testWidgets('El login pide correo y contraseña', (tester) async {
      await abrir(tester, AuthStep.login);

      expect(find.text('Qué bueno verte'), findsOneWidget);
      expect(find.byType(TextFormField), findsNWidgets(2));
    });

    testWidgets('El registro pide los mismos datos que la web', (tester) async {
      await abrir(tester, AuthStep.register);

      expect(find.text('Comienza con Ride'), findsOneWidget);
      // El rol se elige aquí, no antes: es el `.role-picker` de WEB-RIDE.
      expect(find.text('Viajo'), findsOneWidget);
      expect(find.text('Conduzco'), findsOneWidget);
      expect(find.byType(TextFormField), findsNWidgets(4));
      expect(find.text('Nombre completo'), findsOneWidget);
      expect(find.text('Teléfono'), findsOneWidget);
      expect(find.text('Correo electrónico'), findsOneWidget);
      expect(find.text('Contraseña'), findsOneWidget);
    });

    testWidgets('Desde el login se llega a recuperar la contraseña', (
      tester,
    ) async {
      await abrir(tester, AuthStep.login);

      final enlace = find.text('¿Olvidaste tu contraseña?');
      expect(enlace, findsOneWidget);

      await tester.ensureVisible(enlace);
      await tester.pumpAndSettle();
      await tester.tap(enlace);
      await tester.pumpAndSettle();

      expect(find.text('RECUPERAR ACCESO'), findsOneWidget);
      // Solo pide el correo: la contraseña nueva se fija desde el enlace.
      expect(find.byType(TextFormField), findsOneWidget);
      expect(find.text('Enviar enlace'), findsOneWidget);
    });

    testWidgets('El registro no ofrece roles administrativos', (tester) async {
      await abrir(tester, AuthStep.register);

      // Estos dos existen en el enum pero nunca se muestran: las cuentas
      // administrativas las provisiona el equipo, no el formulario público.
      expect(find.text('Administro'), findsNothing);
      expect(find.text('Superadmin'), findsNothing);
    });
  });

  group('Bienvenida adaptable', () {
    for (final size in const [
      Size(280, 653),
      Size(320, 568),
      Size(375, 667),
      Size(400, 653),
      Size(500, 500),
      Size(768, 1024),
      Size(1024, 600),
      Size(1440, 900),
    ]) {
      testWidgets('No desborda en ${size.width}x${size.height}', (
        tester,
      ) async {
        await tester.binding.setSurfaceSize(size);
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark,
            home: WelcomeHomeScreen(onContinue: () {}),
          ),
        );
        await tester.pump(const Duration(milliseconds: 1400));

        final start = find.text('Empezar');
        expect(start, findsOneWidget);
        // Con fuentes de accesibilidad más anchas el contenido puede requerir
        // desplazamiento; el botón debe seguir siendo alcanzable y visible.
        await tester.ensureVisible(start);
        await tester.pumpAndSettle();
        expect(tester.getRect(start).bottom, lessThan(size.height));
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('El acceso oscuro cabe en un teléfono pequeño', (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(theme: AppTheme.dark, home: const AuthScreen()),
      );
      await tester.pumpAndSettle();

      expect(find.text('¿Cómo quieres continuar?'), findsOneWidget);
      expect(find.text('Crear cuenta'), findsOneWidget);
      expect(find.text('Ya tengo una cuenta'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('Rutas', () {
    Ruta ruta({double metros = 5070, int segundos = 462}) => Ruta(
      puntos: const [],
      metros: metros,
      duracion: Duration(seconds: segundos),
    );

    test('La distancia larga se muestra en kilometros', () {
      expect(ruta().distanciaTexto, '5,1 km');
    });

    test('Por debajo del kilometro se muestra en metros', () {
      expect(ruta(metros: 850).distanciaTexto, '850 m');
    });

    test('La duracion pasa a horas cuando toca', () {
      expect(ruta(segundos: 462).duracionTexto, '7 min');
      expect(ruta(segundos: 3900).duracionTexto, '1 h 5 min');
      expect(ruta(segundos: 7200).duracionTexto, '2 h');
    });
  });

  group('Zoom del mapa', () {
    testWidgets('Al acercarse mas alla de z19 se siguen viendo teselas', (
      tester,
    ) async {
      // El mapa usa teselas vectoriales de OpenFreeMap, con las de
      // OpenStreetMap como respaldo. Aqui se comprueba el respaldo, que es lo
      // unico que se puede montar sin red; ademas, dejar que intente cargar el
      // estilo deja un temporizador vivo y la prueba falla por eso.
      MapStyleService.instance.soloRaster = true;
      addTearDown(() => MapStyleService.instance.soloRaster = false);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: const Scaffold(
            body: RideMap(centro: LatLng(-2.1709, -79.9224), zoom: 15),
          ),
        ),
      );

      final capa = tester.widget<TileLayer>(find.byType(TileLayer));

      // OSM solo sirve hasta z19: de ahi en adelante flutter_map reutiliza esa
      // tesela y la escala.
      expect(capa.maxNativeZoom, 19);

      // `maxZoom` es hasta donde se DIBUJA la capa. Fijarlo en 19 dejaba el
      // mapa en negro al hacer mas zoom, que es justo el fallo que esto cuida.
      expect(capa.maxZoom, double.infinity);

      // flutter_map abre una cache en disco que en las pruebas no existe.
      tester.takeException();
    });
  });

  group('El mapa nunca contradice al tema', () {
    // El sintoma que se vio en el telefono: mapa de noche con la app de dia, y
    // al reves. La capa base tiene que ir SIEMPRE con el tema de la app.
    Future<TileLayer> capaCon(WidgetTester tester, ThemeData tema) async {
      MapStyleService.instance.soloRaster = true;
      addTearDown(() => MapStyleService.instance.soloRaster = false);

      await tester.pumpWidget(
        MaterialApp(
          theme: tema,
          home: const Scaffold(
            body: RideMap(centro: LatLng(-0.1807, -78.4678), zoom: 15),
          ),
        ),
      );
      final capa = tester.widget<TileLayer>(find.byType(TileLayer));
      tester.takeException();
      return capa;
    }

    testWidgets('En claro, las teselas no se invierten', (tester) async {
      final capa = await capaCon(tester, AppTheme.light);
      expect(capa.tileBuilder, isNull);
    });

    testWidgets('En oscuro, las teselas se invierten', (tester) async {
      // OSM no publica estilo oscuro: el respaldo rasterizado invierte sus
      // teselas claras. Si esto saliera nulo, el mapa de respaldo se veria
      // blanco encima de una app negra.
      final capa = await capaCon(tester, AppTheme.dark);
      expect(capa.tileBuilder, isNotNull);
    });
  });

  group('Eleccion de ruta', () {
    Ruta ruta({required double km, required int min}) => Ruta(
      puntos: const [],
      metros: km * 1000,
      duracion: Duration(minutes: min),
    );

    test('Sin rutas no hay nada que elegir', () {
      expect(RoutingService.elegirMejor(const []), isNull);
    });

    test('A igual tiempo se queda con la mas corta', () {
      // El caso real medido en Quito: OSRM devolvia 9,29 km y 10,39 km con los
      // mismos 22,6 min, y ordenadas asi. Quedarse con la primera por serlo es
      // jugarsela.
      final elegida = RoutingService.elegirMejor([
        ruta(km: 10.39, min: 22),
        ruta(km: 9.29, min: 22),
      ])!;
      expect(elegida.metros, 9290);
    });

    test('No acepta una ruta mucho mas lenta por ser corta', () {
      // 6 km pero el doble de tiempo: es un atajo por calles malas.
      final elegida = RoutingService.elegirMejor([
        ruta(km: 8, min: 15),
        ruta(km: 6, min: 30),
      ])!;
      expect(elegida.metros, 8000);
    });

    test('Acepta un poco mas de tiempo si recorta bastante', () {
      // 5 % mas lenta, dentro del margen del 10 %, y 2 km mas corta.
      final elegida = RoutingService.elegirMejor([
        ruta(km: 12, min: 20),
        ruta(km: 10, min: 21),
      ])!;
      expect(elegida.metros, 10000);
    });
  });

  group('Hoja de cuenta', () {
    const usuario = AppUser(
      id: 'u1',
      name: 'Diego Andres',
      email: 'diego@ride.app',
      phone: '0999999999',
      role: UserRole.superadmin,
    );

    testWidgets('En una pantalla corta el contenido se desplaza, no desborda', (
      tester,
    ) async {
      // 200 px de alto: el avatar, el correo, la insignia y el boton ya no
      // caben. Es la misma situacion que provocaba una cuenta de superadmin,
      // que ve tres paneles en el selector y desbordaba por abajo cortando
      // «Cerrar sesion».
      tester.view.physicalSize = const Size(390 * 3, 200 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => showAccountSheet(context, usuario),
                  child: const Text('abrir'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();

      // Un desbordamiento de layout llega como excepcion del framework.
      expect(tester.takeException(), isNull);

      // Y el contenido tiene que poder desplazarse para que quepa.
      expect(
        find.descendant(
          of: find.byType(BottomSheet),
          matching: find.byType(Scrollable),
        ),
        findsWidgets,
      );
    });
  });

  group('Cotizacion', () {
    Quote cotizar(Map<String, dynamic> extra) => Quote.fromMap({
      'tarifa_id': 't1',
      'tarifa_nombre': 'Tarifa Estandar',
      'distancia_km': 5.92,
      'minutos_estimados': 15,
      'total': 4.31,
      'gana_conductor': 3.66,
      'comision_app': 0.65,
      'aplico_minima': false,
      ...extra,
    });

    test('Lee el reparto entre chofer y app', () {
      final q = cotizar(const {});
      expect(q.total, 4.31);
      expect(q.ganaConductor, 3.66);
      expect(q.comisionApp, 0.65);
      // Lo que se lleva el chofer mas la comision es lo que paga el pasajero.
      expect(q.ganaConductor + q.comisionApp, closeTo(q.total, 0.001));
    });

    test('El redondeo a centimos no pierde ni inventa dinero', () {
      // El porcentaje vive en la tabla `tarifas`, no en Dart, asi que aqui no
      // se afirma cual es. Lo que si tiene que cumplirse siempre es que las dos
      // partes sumen exactamente lo que paga el pasajero.
      final q = cotizar(const {
        'total': 4.31,
        'gana_conductor': 3.66,
        'comision_app': 0.65,
      });
      expect(q.ganaConductor + q.comisionApp, closeTo(q.total, 0.001));
    });

    test('Marca cuando se aplico la carrera minima', () {
      expect(cotizar(const {}).aplicoMinima, isFalse);
      expect(
        cotizar(const {
          'total': 1.44,
          'gana_conductor': 1.22,
          'comision_app': 0.22,
          'aplico_minima': true,
        }).aplicoMinima,
        isTrue,
      );
    });
  });

  group('Servidor de rutas', () {
    test('Quita la barra final, que duplicaria la de la ruta', () {
      expect(
        RoutingService.normalizar('https://rutas.midominio.com/'),
        'https://rutas.midominio.com',
      );
      expect(
        RoutingService.normalizar('  https://rutas.midominio.com//  '),
        'https://rutas.midominio.com',
      );
    });

    test('Sin configurar cae al servidor de demostracion', () {
      expect(RoutingService.normalizar(''), contains('project-osrm.org'));
      expect(RoutingService.normalizar('   '), contains('project-osrm.org'));
    });

    test('Reconoce los servidores publicos, que no valen para produccion', () {
      expect(
        RoutingService.esServidorPublico('https://router.project-osrm.org'),
        isTrue,
      );
      expect(
        RoutingService.esServidorPublico(
          'https://routing.openstreetmap.de/routed-car',
        ),
        isTrue,
      );
      expect(
        RoutingService.esServidorPublico('https://rutas.midominio.com'),
        isFalse,
      );
    });
  });

  group('Direcciones guardadas', () {
    SavedPlace leer(Map<String, dynamic> extra) => SavedPlace.fromMap({
      'id': 'd1',
      'direccion': 'Avenida Amazonas 123, Quito',
      'latitud': -0.18,
      'longitud': -78.48,
      'favorita': false,
      'etiqueta': null,
      ...extra,
    });

    test('Una direccion del historial no es favorita ni tiene etiqueta', () {
      final d = leer(const {});
      expect(d.favorita, isFalse);
      expect(d.etiqueta, isNull);
    });

    test('Un favorito trae su etiqueta', () {
      // `recordar_direccion` marca favorita cualquier direccion a la que se le
      // ponga nombre, asi que las dos cosas viajan juntas.
      final d = leer(const {'favorita': true, 'etiqueta': 'Casa'});
      expect(d.favorita, isTrue);
      expect(d.etiqueta, 'Casa');
      expect(d.lat, -0.18);
      expect(d.lng, -78.48);
    });
  });

  group('Clave del buscador', () {
    test('Sin clave se usa Photon', () {
      expect(BusquedaConfig.claveValida(''), isFalse);
      expect(BusquedaConfig.claveValida('   '), isFalse);
    });

    test('Una clave de TomTom se acepta', () {
      expect(
        BusquedaConfig.claveValida('rAnDoM4lFaNuM3r1cK3y0fT0mT0m'),
        isTrue,
      );
    });

    test('Una URL pegada por error cae a Photon', () {
      // Mejor un buscador con datos flojos que uno que no encuentra nada.
      expect(
        BusquedaConfig.claveValida('https://developer.tomtom.com/miclave'),
        isFalse,
      );
      expect(BusquedaConfig.claveValida('corta'), isFalse);
    });
  });

  group('Roles', () {
    test('Solo pasajero y conductor se pueden elegir', () {
      expect(UserRole.selectable, [UserRole.passenger, UserRole.driver]);
    });

    test('admin y superadmin son administrativos; los demás no', () {
      expect(UserRole.admin.isAdministrative, isTrue);
      expect(UserRole.superadmin.isAdministrative, isTrue);
      expect(UserRole.passenger.isAdministrative, isFalse);
      expect(UserRole.driver.isAdministrative, isFalse);
    });

    test('fromId acepta los cuatro valores del enum de la base', () {
      // Son los mismos que `public.user_role` en Postgres.
      expect(UserRole.fromId('passenger'), UserRole.passenger);
      expect(UserRole.fromId('driver'), UserRole.driver);
      expect(UserRole.fromId('admin'), UserRole.admin);
      expect(UserRole.fromId('superadmin'), UserRole.superadmin);
    });

    test('Un rol desconocido cae a pasajero, nunca a administrativo', () {
      expect(UserRole.fromId('dios'), UserRole.passenger);
      expect(UserRole.fromId(''), UserRole.passenger);
    });
  });

  group('AppUser', () {
    AppUser usuario({String name = 'Andrea Salazar'}) => AppUser(
      id: 'u-1',
      name: name,
      email: 'andrea@ride.app',
      phone: '0991234567',
      role: UserRole.passenger,
    );

    test('firstName toma solo el primer nombre', () {
      expect(usuario().firstName, 'Andrea');
    });

    test('initials usa las dos primeras palabras', () {
      expect(usuario().initials, 'AS');
      expect(usuario(name: 'Andrea').initials, 'A');
    });

    test('copyWith conserva la identidad y cambia solo lo pedido', () {
      final original = usuario();
      final cambiado = original.copyWith(
        role: UserRole.driver,
        vehicle: const Vehicle(model: 'Kia Rio', plate: 'ABC-1234', year: 2022),
      );

      expect(cambiado.id, original.id);
      expect(cambiado.email, original.email);
      expect(cambiado.role, UserRole.driver);
      expect(cambiado.vehicle?.plate, 'ABC-1234');
    });
  });

  group('Estados del viaje', () {
    test('Los nueve estados coinciden con el enum de Postgres', () {
      // Deben ser exactamente los valores de public.enum_estado_viaje.
      expect(TripStatus.values.map((e) => e.id).toList(), [
        'SOLICITADO',
        'BUSCANDO_CONDUCTOR',
        'ACEPTADO',
        'CONDUCTOR_EN_CAMINO',
        'CONDUCTOR_EN_ORIGEN',
        'EN_CURSO',
        'FINALIZADO',
        'CANCELADO',
        'SIN_CONDUCTOR',
      ]);
    });

    test('Solo finalizado, cancelado y sin chofer cierran el viaje', () {
      final finales = TripStatus.values
          .where((e) => e.esFinal)
          .map((e) => e.id)
          .toSet();
      expect(finales, {'FINALIZADO', 'CANCELADO', 'SIN_CONDUCTOR'});
    });

    test('Un viaje en curso ya no se puede cancelar', () {
      // La persona va a bordo: cancelar ahí no tiene sentido, y la funcion
      // cancelar_viaje() lo rechaza igual del lado del servidor.
      expect(TripStatus.enCurso.sePuedeCancelar, isFalse);
      expect(TripStatus.finalizado.sePuedeCancelar, isFalse);
      expect(TripStatus.solicitado.sePuedeCancelar, isTrue);
      expect(TripStatus.conductorEnOrigen.sePuedeCancelar, isTrue);
    });

    test('Solo hay chofer que mostrar desde que acepta y hasta que cierra', () {
      expect(TripStatus.buscandoConductor.tieneConductor, isFalse);
      expect(TripStatus.aceptado.tieneConductor, isTrue);
      expect(TripStatus.enCurso.tieneConductor, isTrue);
      expect(TripStatus.finalizado.tieneConductor, isFalse);
    });

    test('Un estado desconocido no rompe la app', () {
      expect(TripStatus.fromId('ALGO_RARO'), TripStatus.solicitado);
    });

    test('El progreso avanza con el recorrido', () {
      expect(
        TripStatus.solicitado.progreso,
        lessThan(TripStatus.aceptado.progreso),
      );
      expect(
        TripStatus.aceptado.progreso,
        lessThan(TripStatus.enCurso.progreso),
      );
      expect(TripStatus.finalizado.progreso, 1);
    });
  });

  group('H3', () {
    // Estas pruebas corren en la VM de Dart, no en el navegador, así que H3
    // NO está disponible aquí. Es justo lo que interesa comprobar: que la app
    // siga funcionando donde H3 no existe.
    test('Fuera de la web, H3 se reporta como no disponible', () {
      expect(H3Service.instance.disponible, isFalse);
    });

    test('Sin H3 las celdas son null, no una excepción', () {
      // Si esto lanzara, pedir un viaje fallaría en móvil.
      expect(H3Service.instance.celda(-2.1574, -79.8836), isNull);
      expect(H3Service.instance.celdaZona(-2.1574, -79.8836), isNull);
      expect(H3Service.instance.disco(-2.1574, -79.8836), isNull);
    });

    test('El radio coincide con el de PostGIS', () {
      // Si se separan, las dos vías darían resultados distintos y la
      // comparación dejaría de tener sentido.
      expect(H3Service.radioKm, 5);
    });

    test('La resolución de difusión es la medida como mejor equilibrio', () {
      // res 7: 61 celdas por consulta. res 8 sube a 331 y res 9 a 1951 sin
      // ganar precisión.
      expect(H3Service.resDifusion, 7);
      expect(H3Service.resZona, greaterThan(H3Service.resDifusion));
    });
  });

  group('Geocodificación', () {
    test('El texto completo une nombre y contexto', () {
      const p = GeoPlace(
        nombre: 'Calle de Serrano 21',
        direccion: 'Madrid, España',
        lat: 40.42,
        lng: -3.68,
      );
      expect(p.completo, 'Calle de Serrano 21, Madrid, España');
    });

    test('Sin contexto no queda una coma suelta', () {
      const p = GeoPlace(
        nombre: 'Tu ubicación actual',
        direccion: '',
        lat: 0,
        lng: 0,
      );
      expect(p.completo, 'Tu ubicación actual');
    });

    test('Textos muy cortos no salen a la red', () async {
      // Photon ignora consultas de una o dos letras y solo gastarían batería.
      expect(await GeocodingService.instance.buscar('a'), isEmpty);
      expect(await GeocodingService.instance.buscar('ab'), isEmpty);
      expect(await GeocodingService.instance.buscar('   '), isEmpty);
    });
  });

  group('Flota y documentos', () {
    test('Los cuatro tipos coinciden con el CHECK de la base', () {
      // El orden importa: es el que ve el chofer al subirlos y el que sigue la
      // administración al revisarlos. La cédula va primero porque identifica a
      // la persona; el resto habilita a conducir y al vehículo.
      expect(DocumentType.values.map((d) => d.id).toList(), [
        'cedula',
        'licencia',
        'SOAT',
        'matricula',
      ]);
    });

    test('Los estados coinciden con el CHECK de la base', () {
      expect(DocumentStatus.values.map((d) => d.id).toList(), [
        'pendiente',
        'aprobado',
        'rechazado',
      ]);
    });

    test('Un tipo o estado desconocido no rompe la app', () {
      expect(DocumentType.fromId('pasaporte'), DocumentType.licencia);
      expect(DocumentStatus.fromId('raro'), DocumentStatus.pendiente);
    });

    test('El resumen del vehículo se arma para mostrarlo al pasajero', () {
      const v = FleetVehicle(
        id: 'v-1',
        placa: 'ABC-1234',
        marca: 'Kia',
        modelo: 'Rio',
        anio: 2022,
        activo: true,
        color: 'Blanco',
      );
      expect(v.resumen, 'Kia Rio · 2022');
    });
  });

  group('Métodos de pago', () {
    test('El efectivo se describe sin exponer nada', () {
      const m = PaymentMethod(
        id: 'm-1',
        tipo: 'efectivo',
        predeterminado: true,
      );
      expect(m.esEfectivo, isTrue);
      expect(m.label, 'Efectivo');
      expect(m.descripcion, 'Pagas al llegar');
    });

    test('De la tarjeta solo se muestran los últimos caracteres del token', () {
      // Nunca es un número de tarjeta: la base rechaza cualquier cosa con
      // forma de PAN. Aun así, del token tampoco se enseña todo.
      const m = PaymentMethod(
        id: 'm-2',
        tipo: 'tarjeta',
        predeterminado: false,
        detalle: 'tok_abc123XYZ9',
      );
      expect(m.descripcion, '···· XYZ9');
      expect(m.descripcion.contains('tok_abc'), isFalse);
    });

    test('Un token muy corto no se recorta a la fuerza', () {
      const m = PaymentMethod(
        id: 'm-3',
        tipo: 'tarjeta',
        predeterminado: false,
        detalle: 'ab',
      );
      expect(m.descripcion, 'Tarjeta guardada');
    });
  });

  group('Notificaciones', () {
    AppNotification aviso(Duration antiguedad) => AppNotification(
      id: 'n-1',
      titulo: 'Chofer asignado',
      mensaje: 'Va en camino',
      leida: false,
      fecha: DateTime.now().subtract(antiguedad),
    );

    test('El texto relativo se adapta a la antigüedad', () {
      expect(aviso(const Duration(seconds: 20)).cuando, 'ahora');
      expect(aviso(const Duration(minutes: 5)).cuando, 'hace 5 min');
      expect(aviso(const Duration(hours: 3)).cuando, 'hace 3 h');
      expect(aviso(const Duration(days: 1, hours: 1)).cuando, 'ayer');
      expect(aviso(const Duration(days: 4)).cuando, 'hace 4 días');
    });
  });

  group('Acceso entre paneles', () {
    test('El superadmin llega a los cuatro paneles', () {
      expect(UserRole.superadmin.viewsAllowed(), [
        UserRole.superadmin,
        UserRole.admin,
        UserRole.passenger,
        UserRole.driver,
      ]);
    });

    test('Ver la pantalla de chofer no convierte a nadie en chofer', () {
      // La lista de vistas es de presentacion. Que un superadmin pueda abrir
      // la pantalla de chofer no le da permisos de chofer: eso lo decide la
      // base, y ahi el trigger validar_disponibilidad_conductor_real() le
      // impide ponerse en linea. Esta prueba fija esa separacion para que no
      // se confunda «puedo mirarlo» con «puedo hacerlo».
      expect(
        UserRole.superadmin.viewsAllowed().contains(UserRole.driver),
        isTrue,
      );
      expect(UserRole.superadmin.isDriver, isFalse);
    });

    test('El admin NO puede abrir la vista de superadmin', () {
      final vistas = UserRole.admin.viewsAllowed();
      expect(vistas.contains(UserRole.superadmin), isFalse);
      expect(vistas, [UserRole.admin, UserRole.passenger, UserRole.driver]);
    });

    test('Las dos cuentas administrativas llegan a usuario y chofer', () {
      // Poder abrirlas no las iguala: en la base, pedir un viaje lo puede
      // cualquiera de las dos, pero ponerse en linea y aceptar carreras solo
      // admite ('driver', 'superadmin'). El admin entra a la vista de chofer a
      // revisarla; trabajar desde ella lo sigue bloqueando Postgres.
      for (final rol in [UserRole.admin, UserRole.superadmin]) {
        final vistas = rol.viewsAllowed();
        expect(vistas, contains(UserRole.passenger), reason: rol.id);
        expect(vistas, contains(UserRole.driver), reason: rol.id);
        expect(rol.isDriver, isFalse, reason: rol.id);
      }
    });

    test('Ningún rol no administrativo alcanza un panel administrativo', () {
      for (final rol in [UserRole.passenger, UserRole.driver]) {
        final vistas = rol.viewsAllowed(hasVehicle: true);
        expect(vistas.any((v) => v.isAdministrative), isFalse, reason: rol.id);
      }
    });

    test('Todos pueden volver a su propio panel', () {
      for (final rol in UserRole.values) {
        expect(
          rol.viewsAllowed(hasVehicle: true),
          contains(rol),
          reason: rol.id,
        );
      }
    });

    test('Un pasajero sin vehículo no puede abrir la vista de chofer', () {
      expect(UserRole.passenger.viewsAllowed(), [UserRole.passenger]);
      expect(UserRole.passenger.viewsAllowed(hasVehicle: true), [
        UserRole.passenger,
      ]);
    });
  });

  group('Etiquetas de panel', () {
    test('Cada vista se nombra como pantalla, no como rol', () {
      // Importa la distinción: un superadmin que abre la vista de pasajero no
      // pasa a ser pasajero, solo mira esa pantalla.
      expect(panelLabel(UserRole.superadmin), 'Panel de superadmin');
      expect(panelLabel(UserRole.admin), 'Panel de administración');
      expect(panelLabel(UserRole.passenger), 'Vista de usuario');
      expect(panelLabel(UserRole.driver), 'Vista de chofer');
    });
  });

  group('AuthService', () {
    test('Sin sesión no hay vistas disponibles', () {
      expect(AuthService.instance.availableViews, isEmpty);
    });

    test('Sin sesión, cambiar de vista no hace nada', () {
      // No debe lanzar: simplemente no hay nada que cambiar.
      AuthService.instance.switchView(UserRole.admin);
      expect(AuthService.instance.isViewingOtherPanel, isFalse);
    });

    test(
      'El registro rechaza roles administrativos antes de salir a la red',
      () async {
        // La validación es local, así que no necesita sesión ni conexión: el
        // trigger handle_new_user() es la segunda barrera, no la única.
        await expectLater(
          AuthService.instance.register(
            name: 'Intruso',
            email: 'intruso@ride.app',
            phone: '0990000000',
            password: 'ClaveLarga123',
            role: UserRole.superadmin,
          ),
          throwsA(isA<AuthException>()),
        );
      },
    );

    test('Sin sesión no se puede consultar la lista de usuarios', () async {
      await expectLater(
        AuthService.instance.visibleUsers(),
        throwsA(isA<AuthException>()),
      );
    });

    test('Sin sesión no se puede cambiar la contraseña inicial', () async {
      await expectLater(
        AuthService.instance.changeInitialPassword('ClaveDefinitiva123'),
        throwsA(isA<AuthException>()),
      );
    });
  });

  // ---------------------------------------------------------------------------
  // Lo que tiene que sobrevivir a que se cierre la app
  // ---------------------------------------------------------------------------

  group('Guardar el viaje en el teléfono', () {
    // `TripSessionStore` guarda el viaje como JSON y lo reconstruye al
    // arrancar. Si `toMap` y `fromMap` dejan de hablar el mismo idioma, la app
    // reabriría con datos a medias y nadie se enteraría hasta verlo en un
    // teléfono. Por eso se prueba la ida y la vuelta, no cada campo suelto.
    final viaje = Trip(
      id: 'v-1',
      status: TripStatus.conductorEnCamino,
      pasajeroId: 'p-1',
      conductorId: 'c-1',
      tarifaEstimada: 4.25,
      fechaSolicitud: DateTime(2026, 8, 31, 14, 30),
      tarifaNombre: 'Diurna',
      pasajeroNombre: 'Andrea',
      conductorNombre: 'Diego',
      conductorTelefono: '0999999999',
      vehiculoPlaca: 'PDC-1234',
      vehiculoMarca: 'Kia',
      vehiculoModelo: 'Rio',
      origenTexto: 'La Carolina',
      destinoTexto: 'Cumbayá',
      origenLat: -0.1807,
      origenLng: -78.4678,
      destinoLat: -0.2050,
      destinoLng: -78.4300,
    );

    test('La referencia para el chofer sobrevive al guardado', () {
      // Es el dato que salva los sitios que no estan en ningun mapa: si se
      // perdiera al cerrar y reabrir la app, el chofer se quedaria sin saber
      // como encontrar a la persona justo cuando mas falta hace.
      final conReferencia = Trip.fromMap({
        ...viaje.toMap(),
        'origen_referencia': 'Edificio Blanco con porton azul, 3 pisos',
        'destino_referencia': 'Entrada por la calle de atras',
      });
      final copia = Trip.fromMap(conReferencia.toMap());

      expect(
        copia.origenReferencia,
        'Edificio Blanco con porton azul, 3 pisos',
      );
      expect(copia.destinoReferencia, 'Entrada por la calle de atras');
    });

    test('Un viaje sin referencia no se inventa una', () {
      expect(Trip.fromMap(viaje.toMap()).origenReferencia, isNull);
      expect(Trip.fromMap(viaje.toMap()).destinoReferencia, isNull);
    });

    test('Un viaje guardado y releído es el mismo viaje', () {
      final copia = Trip.fromMap(viaje.toMap());

      expect(copia.id, viaje.id);
      expect(copia.status, viaje.status);
      expect(copia.conductorId, viaje.conductorId);
      expect(copia.tarifaEstimada, viaje.tarifaEstimada);
      expect(copia.fechaSolicitud, viaje.fechaSolicitud);
      expect(copia.conductorNombre, viaje.conductorNombre);
      expect(copia.vehiculoPlaca, viaje.vehiculoPlaca);
      expect(copia.origenTexto, viaje.origenTexto);
      expect(copia.destinoTexto, viaje.destinoTexto);
      expect(copia.origenLat, viaje.origenLat);
      expect(copia.destinoLng, viaje.destinoLng);
    });

    test('Los estados sin fecha no se inventan una al releerse', () {
      final copia = Trip.fromMap(viaje.toMap());
      expect(copia.fechaInicio, isNull);
      expect(copia.fechaFin, isNull);
      expect(copia.tarifaFinal, isNull);
    });
  });

  group('Rutas guardadas', () {
    // La ruta del viaje se guarda en el teléfono para que al reabrir la app se
    // vea en el primer frame en vez de esperar a OSRM.
    final ruta = Ruta(
      puntos: const [
        LatLng(-0.180700, -78.467800),
        LatLng(-0.190123, -78.450456),
        LatLng(-0.205000, -78.430000),
      ],
      metros: 4820,
      duracion: const Duration(minutes: 13),
    );

    test('Una ruta guardada y releída dibuja el mismo trazado', () {
      final copia = Ruta.desdeJson(ruta.aJson())!;

      expect(copia.puntos.length, ruta.puntos.length);
      expect(copia.metros, ruta.metros);
      expect(copia.duracion, ruta.duracion);
      // Se guarda con cinco decimales —un metro— así que se compara con esa
      // tolerancia, no por igualdad exacta.
      for (var i = 0; i < ruta.puntos.length; i++) {
        expect(
          copia.puntos[i].latitude,
          closeTo(ruta.puntos[i].latitude, 0.00001),
        );
        expect(
          copia.puntos[i].longitude,
          closeTo(ruta.puntos[i].longitude, 0.00001),
        );
      }
    });

    test('Una caché corrupta devuelve null en vez de romper el mapa', () {
      expect(Ruta.desdeJson({'basura': true}), isNull);
      // Con un solo punto no hay línea que dibujar.
      expect(
        Ruta.desdeJson({
          'm': 10.0,
          's': 5,
          'p': [
            [-0.1, -78.4],
          ],
        }),
        isNull,
      );
    });
  });

  // ---------------------------------------------------------------------------
  // Revisión de conductores
  // ---------------------------------------------------------------------------

  group('Ficha de revisión del conductor', () {
    /// Una fila como la que devuelve `public.conductores_revision`.
    Map<String, dynamic> fila({
      List<String> aprobados = const [],
      List<String> pendientes = const [],
      bool conAuto = true,
      String? nombre = 'Javier Conforme',
    }) {
      return {
        'id': 'c-1',
        'nombre': nombre,
        'email': 'javier@ride.app',
        'telefono': '0988888888',
        'foto_url': null,
        'estado_aprobacion': 'pendiente',
        'disponible': false,
        'calificacion_promedio': null,
        'fecha_registro': '2026-08-20T10:00:00Z',
        'vehiculos': conAuto
            ? [
                {
                  'id': 'v-1',
                  'placa': 'PDC-1234',
                  'marca': 'Kia',
                  'modelo': 'Rio',
                  'anio': 2022,
                  'color': 'Blanco',
                  'activo': true,
                },
              ]
            : <Map<String, dynamic>>[],
        'documentos': [
          for (final tipo in aprobados)
            {
              'id': 'd-$tipo',
              'tipo_documento': tipo,
              'estado': 'aprobado',
              'url_archivo': 'c-1/$tipo.jpg',
              'fecha_subida': '2026-08-21T10:00:00Z',
            },
          for (final tipo in pendientes)
            {
              'id': 'd-$tipo',
              'tipo_documento': tipo,
              'estado': 'pendiente',
              'url_archivo': 'c-1/$tipo.jpg',
              'fecha_subida': '2026-08-21T10:00:00Z',
            },
        ],
      };
    }

    test('Sin documentos, faltan los cuatro', () {
      final conductor = DriverReview.fromMap(fila());
      expect(conductor.faltantes.length, DocumentType.values.length);
      expect(conductor.listoParaAprobar, isFalse);
    });

    test('Un documento subido pero sin revisar sigue faltando', () {
      // Es la trampa de contar «documentos entregados» en vez de «aprobados»:
      // subirlos no es lo mismo que validarlos.
      final conductor = DriverReview.fromMap(
        fila(pendientes: ['cedula', 'licencia', 'SOAT', 'matricula']),
      );
      expect(conductor.pendientes, 4);
      expect(conductor.aprobados, 0);
      expect(conductor.listoParaAprobar, isFalse);
    });

    test('Con los cuatro aprobados y un auto, se puede aprobar', () {
      final conductor = DriverReview.fromMap(
        fila(aprobados: ['cedula', 'licencia', 'SOAT', 'matricula']),
      );
      expect(conductor.faltantes, isEmpty);
      expect(conductor.listoParaAprobar, isTrue);
    });

    test('Con los papeles en regla pero sin vehículo, todavía no', () {
      // Es la misma condición que exige `revisar_conductor`: aprobar aquí
      // solo daría un error del servidor.
      final conductor = DriverReview.fromMap(
        fila(
          aprobados: ['cedula', 'licencia', 'SOAT', 'matricula'],
          conAuto: false,
        ),
      );
      expect(conductor.faltantes, isEmpty);
      expect(conductor.listoParaAprobar, isFalse);
    });

    test('Sin nombre se usa el correo, para que la fila no salga vacía', () {
      final conductor = DriverReview.fromMap(fila(nombre: null));
      expect(conductor.nombre, 'javier');
      expect(conductor.iniciales, 'J');
    });
  });

  group('Posicion del chofer', () {
    DriverPosition pos(Duration hace) => DriverPosition(
      lat: -0.18,
      lng: -78.49,
      cuando: DateTime.now().subtract(hace),
    );

    test('Una posicion recien reportada es de fiar', () {
      expect(pos(const Duration(seconds: 20)).esVieja, isFalse);
      expect(pos(const Duration(minutes: 2)).esVieja, isFalse);
    });

    test('Pasados tres minutos, deja de serlo', () {
      // El chofer reporta cada 30 segundos. Tres minutos sin noticias es que
      // se quedo sin datos, y el alfiler del mapa esta mintiendo.
      expect(pos(const Duration(minutes: 3)).esVieja, isTrue);
      expect(pos(const Duration(hours: 1)).esVieja, isTrue);
    });

    test('La antiguedad se escribe en palabras', () {
      expect(pos(const Duration(seconds: 5)).cuandoTexto, 'ahora mismo');
      expect(pos(const Duration(minutes: 1)).cuandoTexto, 'hace 1 minuto');
      expect(pos(const Duration(minutes: 12)).cuandoTexto, 'hace 12 minutos');
      expect(pos(const Duration(hours: 1)).cuandoTexto, 'hace 1 hora');
    });
  });

  group('Tipos de vehiculo', () {
    VehicleCategory cat(String id, String icono, int pasajeros) =>
        VehicleCategory.fromMap({
          'id': id,
          'nombre': id,
          'descripcion': '',
          'pasajeros': pasajeros,
          'icono': icono,
          'orden': 1,
        });

    test('Cada tipo tiene su propio icono', () {
      final iconos = {
        for (final i in ['moto', 'auto', 'confort', 'van'])
          i: VehicleCategory.iconoDe(i),
      };
      // Cuatro tipos, cuatro dibujos distintos: si dos compartieran icono, en
      // el selector no se distinguirian de un vistazo.
      expect(iconos.values.toSet().length, 4);
    });

    test('Un icono desconocido no rompe la pantalla', () {
      // La base puede ganar una categoria nueva sin que la app se actualice.
      expect(VehicleCategory.iconoDe('helicoptero'), isNotNull);
      expect(VehicleCategory.iconoDe(null), isNotNull);
    });

    test('La capacidad se escribe en singular y en plural', () {
      expect(cat('moto', 'moto', 1).capacidad, '1 pasajero');
      expect(cat('xl', 'van', 6).capacidad, 'hasta 6 pasajeros');
    });

    test('El precio de cada tipo llega del servidor, no se calcula aqui', () {
      // Se leen tal cual: multiplicarlos en el cliente por el factor daria
      // numeros que no cuadran con el cobro, porque el redondeo y la carrera
      // minima no son lineales.
      final q = CategoryQuote.fromMap({
        'categoria': 'moto',
        'nombre': 'Moto',
        'descripcion': 'Rapido y economico',
        'pasajeros': 1,
        'icono': 'moto',
        'orden': 1,
        'total': 3.56,
        'distancia_km': 6.2,
        'minutos_estimados': 14,
        'gana_conductor': 3.03,
        'aplico_minima': false,
      });

      expect(q.categoria.id, 'moto');
      expect(q.total, 3.56);
      expect(q.ganaConductor, 3.03);
      expect(q.categoria.capacidad, '1 pasajero');
    });
  });

  group('Soporte', () {
    Map<String, dynamic> fila({String estado = 'abierto', String? respuesta}) =>
        {
          'id': 't-1',
          'usuario_id': 'u-1',
          'viaje_id': null,
          'categoria': 'pago',
          'asunto': 'Me cobraron de mas',
          'mensaje': 'El viaje decia 3,20 y me cobraron 4,10.',
          'estado': estado,
          'respuesta': respuesta,
          'respondido_en': respuesta == null ? null : '2026-09-02T10:00:00Z',
          'created_at': '2026-09-02T09:00:00Z',
        };

    test('Un caso sin responder no aparece como respondido', () {
      final t = SupportTicket.fromMap(fila());
      expect(t.respondido, isFalse);
      expect(t.estado, TicketStatus.abierto);
      expect(t.categoria, TicketCategory.pago);
    });

    test('Una respuesta en blanco no cuenta como respuesta', () {
      // La base guarda null cuando se envia vacia, pero un espacio suelto
      // colandose dejaria el bloque verde de «Respuesta de Ride» sin nada
      // dentro.
      expect(SupportTicket.fromMap(fila(respuesta: '   ')).respondido, isFalse);
      expect(
        SupportTicket.fromMap(fila(respuesta: 'Ya te devolvimos')).respondido,
        isTrue,
      );
    });

    test('Resuelto y cerrado son estados finales; abierto no', () {
      expect(TicketStatus.resuelto.esFinal, isTrue);
      expect(TicketStatus.cerrado.esFinal, isTrue);
      expect(TicketStatus.abierto.esFinal, isFalse);
      expect(TicketStatus.enProceso.esFinal, isFalse);
    });

    test('Una categoria desconocida cae en «otro»', () {
      expect(TicketCategory.fromId('extraterrestre'), TicketCategory.otro);
      expect(TicketCategory.fromId(null), TicketCategory.otro);
    });
  });

  group('Tarifas editables', () {
    Fare tarifa({double base = 0.40, double km = 0.30, double minima = 1.25}) =>
        Fare.fromMap({
          'id': 'f-1',
          'nombre': 'Tarifa Estandar',
          'tarifa_base': base,
          'costo_por_km': km,
          'costo_por_minuto': 0.08,
          'carrera_minima': minima,
          'porcentaje_conductor': 0.85,
          'activo': true,
          'hora_desde': null,
          'hora_hasta': null,
        });

    test('El ejemplo es arranque mas distancia', () {
      // La misma cuenta que hace cotizar_viaje: si esto se separa, el panel
      // ensenaria un precio que no es el que se cobra.
      expect(tarifa().ejemplo(5), closeTo(0.40 + 0.30 * 5, 0.001));
    });

    test('La carrera minima hace de suelo', () {
      // Un viaje de 300 m no puede salir por debajo de la minima.
      expect(tarifa().ejemplo(0.3), 1.25);
    });

    test('Sin franja horaria, es la de por defecto', () {
      expect(tarifa().franja, 'El resto del día');
    });

    Fare conFranja(int desde, int hasta, List<int>? dias) => Fare.fromMap({
      'id': 'f-2',
      'nombre': 'Tarifa',
      'tarifa_base': 0.49,
      'costo_por_km': 0.35,
      'costo_por_minuto': 0.10,
      'carrera_minima': 1.40,
      'porcentaje_conductor': 0.85,
      'activo': true,
      'hora_desde': desde,
      'hora_hasta': hasta,
      'dias': dias,
    });

    test('La franja termina en :59, que es hasta donde llega el servidor', () {
      // tarifa_vigente() compara la hora entera con un `between`, asi que
      // hora_hasta = 8 cubre hasta las 08:59. Escribir «08:00» hacia creer
      // que la franja terminaba una hora antes de lo que termina, y ese
      // mismo error estuvo cobrando hora pico a las 09:45.
      expect(
        conFranja(6, 8, [1, 2, 3, 4, 5]).franja,
        '06:00 – 08:59, de lunes a viernes',
      );
    });

    test('Sin dias, la franja no menciona ninguno', () {
      // La nocturna aplica todos los dias: `dias` en null.
      expect(conFranja(22, 4, null).franja, '22:00 – 04:59');
    });

    test('Unos dias sueltos se listan, no se leen como rango', () {
      expect(
        conFranja(16, 19, [3, 1]).franja,
        '16:00 – 19:59, lunes, miércoles',
      );
    });

    test('Un dia fuera de 1..7 se descarta en vez de romper la pantalla', () {
      expect(
        conFranja(16, 19, [1, 2, 9]).franja,
        '16:00 – 19:59, lunes, martes',
      );
    });
  });

  group('Tema elegido', () {
    test('Las tres opciones tienen nombre, explicación e icono propios', () {
      final etiquetas = ThemeMode.values.map(ThemeController.etiqueta).toSet();
      final detalles = ThemeMode.values.map(ThemeController.detalle).toSet();
      final iconos = ThemeMode.values.map(ThemeController.icono).toSet();

      expect(etiquetas.length, ThemeMode.values.length);
      expect(detalles.length, ThemeMode.values.length);
      expect(iconos.length, ThemeMode.values.length);
    });

    test('Sin nada guardado, manda el ajuste del teléfono', () {
      // `cargar` sin preferencias abiertas cae al valor por defecto. Es lo que
      // pasa en un teléfono nuevo y en cualquier arranque donde el
      // almacenamiento local falle.
      ThemeController.instance.cargar();
      expect(ThemeController.instance.mode, ThemeMode.system);
    });
  });
}
