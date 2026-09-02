/// Conexión con el proyecto Supabase de Ride.
///
/// La clave *publishable* está pensada para vivir en el cliente: lo que
/// protege los datos son las políticas RLS, no el secreto de la clave. Por eso
/// puede ir compilada en el APK, igual que va en el paquete de WEB-RIDE.
///
/// Nunca poner aquí la clave `service_role`: esa sí es un secreto y solo va en
/// servidor o consola privada.
///
/// Ambos valores se pueden sobreescribir al compilar, por ejemplo para apuntar
/// a un proyecto de pruebas:
///
/// ```sh
/// flutter build apk --release \
///   --dart-define=SUPABASE_URL=https://otro.supabase.co \
///   --dart-define=SUPABASE_PUBLISHABLE_KEY=sb_publishable_otra
/// ```
class SupabaseConfig {
  const SupabaseConfig._();

  static const String url = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://jnnesfafbrlbycfkruph.supabase.co',
  );

  static const String publishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
    defaultValue: 'sb_publishable_49iWrfaCbMnmC2x1xgOnFA_ZT2rFmpV',
  );
}
