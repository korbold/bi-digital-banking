import 'dart:async';

import 'package:core_network/core_network.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

/// Demo panel to reproduce degraded scenarios live on a real device:
/// high latency, random failures, forced offline and per-service outages.
/// Also shows circuit breaker states so the audience sees the breaker open.
class ChaosPanelPage extends StatefulWidget {
  const ChaosPanelPage({
    required this.chaos,
    required this.breakers,
    required this.onClearCache,
    super.key,
  });

  final ChaosController chaos;
  final CircuitBreakerRegistry breakers;
  final Future<void> Function() onClearCache;

  static const services = ['accounts', 'home', 'fx', 'transfers', 'insurance'];

  @override
  State<ChaosPanelPage> createState() => _ChaosPanelPageState();
}

class _ChaosPanelPageState extends State<ChaosPanelPage> {
  // Breaker state changes as the app makes requests; repaint every second.
  late final Timer _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(
      const Duration(seconds: 1),
      (_) => setState(() {}),
    );
  }

  @override
  void dispose() {
    _ticker.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Escenarios degradados'),
      actions: [
        TextButton(
          onPressed: () => setState(widget.chaos.reset),
          child: const Text('Restablecer'),
        ),
      ],
    ),
    body: ValueListenableBuilder<ChaosConfig>(
      valueListenable: widget.chaos,
      builder: (context, config, _) => ListView(
        padding: const EdgeInsets.all(BiSpacing.md),
        children: [
          const StatusBanner(
            message:
                'Las fallas se inyectan en la capa de transporte: reintentos, circuit breaker y caché reaccionan como ante una falla real.',
          ),
          const SizedBox(height: BiSpacing.md),
          SwitchListTile(
            title: const Text('Sin conexión'),
            subtitle: const Text(
              'Todas las solicitudes fallan como si no hubiera red',
            ),
            value: config.forceOffline,
            onChanged: (v) =>
                widget.chaos.value = config.copyWith(forceOffline: v),
          ),
          ListTile(
            title: const Text('Latencia adicional'),
            subtitle: Text('${config.extraLatency.inMilliseconds} ms'),
          ),
          Slider(
            value: config.extraLatency.inMilliseconds.toDouble(),
            max: 8000,
            divisions: 16,
            label: '${config.extraLatency.inMilliseconds} ms',
            onChanged: (v) => widget.chaos.value = config.copyWith(
              extraLatency: Duration(milliseconds: v.round()),
            ),
          ),
          ListTile(
            title: const Text('Tasa de fallas aleatorias'),
            subtitle: Text(
              '${(config.failureRate * 100).round()} % de solicitudes con 503',
            ),
          ),
          Slider(
            value: config.failureRate,
            divisions: 10,
            label: '${(config.failureRate * 100).round()} %',
            onChanged: (v) =>
                widget.chaos.value = config.copyWith(failureRate: v),
          ),
          const SectionHeader('Servicios caídos (indisponibilidad parcial)'),
          for (final service in ChaosPanelPage.services)
            CheckboxListTile(
              title: Text(service),
              subtitle: Text('Circuit breaker: ${_breakerLabel(service)}'),
              value: config.downServices.contains(service),
              onChanged: (_) => widget.chaos.toggleService(service),
            ),
          const SizedBox(height: BiSpacing.md),
          OutlinedButton.icon(
            onPressed: () async {
              await widget.onClearCache();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Caché local borrada')),
                );
              }
            },
            icon: const Icon(Icons.delete_sweep_outlined),
            label: const Text('Borrar caché local'),
          ),
        ],
      ),
    ),
  );

  String _breakerLabel(String service) =>
      switch (widget.breakers.snapshot()[service]) {
        CircuitState.open => 'ABIERTO (falla rápida)',
        CircuitState.halfOpen => 'semiabierto (probando)',
        CircuitState.closed || null => 'cerrado',
      };
}
