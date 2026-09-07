import 'package:flutter/material.dart';

import '../core/ride_colors.dart';
import '../models/fleet.dart';

/// Deja al chofer elegir en qué zonas trabaja.
///
/// Devuelve los ids elegidos, o `null` si cerró sin guardar. La lista vacía es
/// una respuesta válida y distinta de `null`: significa «sin zonas», que no es
/// quedarse sin trabajo sino sin filtro.
Future<List<String>?> mostrarSelectorDeZonas(
  BuildContext context, {
  required List<WorkZone> zonas,
}) {
  return showModalBottomSheet<List<String>>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _SelectorDeZonas(zonas: zonas),
  );
}

class _SelectorDeZonas extends StatefulWidget {
  const _SelectorDeZonas({required this.zonas});

  final List<WorkZone> zonas;

  @override
  State<_SelectorDeZonas> createState() => _SelectorDeZonasState();
}

class _SelectorDeZonasState extends State<_SelectorDeZonas> {
  late final Set<String> _elegidas = {
    for (final z in widget.zonas)
      if (z.elegida) z.id,
  };

  @override
  Widget build(BuildContext context) {
    final ride = context.ride;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Dónde trabajas',
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w800,
                color: ride.ink,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Solo te llegan carreras que salen de estas zonas, y solo '
              'mientras estés dentro de alguna.',
              style: TextStyle(fontSize: 12, color: ride.inkMuted),
            ),
            const SizedBox(height: 16),
            if (widget.zonas.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text(
                  'No se pudieron cargar las zonas. Revisa tu conexión.',
                  style: TextStyle(color: ride.inkMuted),
                ),
              )
            else
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      for (final zona in widget.zonas)
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          value: _elegidas.contains(zona.id),
                          onChanged: (v) => setState(() {
                            if (v == true) {
                              _elegidas.add(zona.id);
                            } else {
                              _elegidas.remove(zona.id);
                            }
                          }),
                          title: Text(zona.nombre),
                        ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 8),
            // Sin ninguna marcada no se le corta el trabajo: recibe de toda la
            // ciudad, como antes de que existieran las zonas. Se dice aquí para
            // que quien las desmarque todas sepa qué acaba de hacer.
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: ride.infoSoft,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline, size: 18, color: ride.info),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _elegidas.isEmpty
                          ? 'Sin ninguna marcada recibes de toda la ciudad.'
                          : 'Fuera de estas zonas no te llegará nada.',
                      style: TextStyle(fontSize: 12, color: ride.ink),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () =>
                    Navigator.of(context).pop(_elegidas.toList()),
                child: const Text('Guardar zonas'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
