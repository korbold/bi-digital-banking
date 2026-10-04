import 'dart:async';

import 'package:design_system/design_system.dart';
import 'package:feature_miniapps/src/bridge.dart';
import 'package:feature_miniapps/src/mini_app.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Hosts a web micro-app inside the native shell with a restricted JS bridge.
///
/// Pops with whatever the micro-app passes to `close({result})`.
class MiniAppPage extends StatefulWidget {
  const MiniAppPage({
    required this.miniApp,
    required this.getContext,
    required this.getAuthToken,
    super.key,
    this.params = const {},
    this.onTrack,
  });

  final MiniAppDescriptor miniApp;
  final Map<String, Object?> params;
  final Future<Map<String, Object?>> Function() getContext;
  final Future<String?> Function() getAuthToken;
  final void Function(String event, Map<String, Object?> params)? onTrack;

  @override
  State<MiniAppPage> createState() => _MiniAppPageState();
}

class _MiniAppPageState extends State<MiniAppPage> implements MiniAppHost {
  late final WebViewController _controller;
  late final MiniAppBridge _bridge;
  int _progress = 0;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _bridge = MiniAppBridge(this);
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel(
        'BiBridge',
        onMessageReceived: (message) =>
            unawaited(_onBridgeMessage(message.message)),
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) {
            final uri = Uri.tryParse(request.url);
            return uri != null && widget.miniApp.allowsNavigation(uri)
                ? NavigationDecision.navigate
                : NavigationDecision.prevent;
          },
          onProgress: (p) => mounted ? setState(() => _progress = p) : null,
          onWebResourceError: (error) {
            if ((error.isForMainFrame ?? true) && mounted) {
              setState(() => _failed = true);
            }
          },
        ),
      );
    _load();
  }

  void _load() {
    setState(() {
      _failed = false;
      _progress = 0;
    });
    unawaited(_controller.loadRequest(widget.miniApp.launchUri(widget.params)));
  }

  Future<void> _onBridgeMessage(String raw) async {
    final response = await _bridge.handle(raw);
    final script = response.script;
    if (script != null && mounted) await _controller.runJavaScript(script);
  }

  // MiniAppHost
  @override
  Future<Map<String, Object?>> getContext() => widget.getContext();

  @override
  Future<String?> getAuthToken() => widget.getAuthToken();

  @override
  void track(String event, Map<String, Object?> params) =>
      widget.onTrack?.call(event, {'miniapp': widget.miniApp.id, ...params});

  @override
  void notifyHost(String title, String body) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(body.isEmpty ? title : '$title · $body')),
    );
  }

  @override
  void close(Object? result) {
    if (mounted) Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.miniApp.title),
      bottom: _progress < 100 && !_failed
          ? PreferredSize(
              preferredSize: const Size.fromHeight(3),
              child: LinearProgressIndicator(
                value: _progress / 100,
                minHeight: 3,
              ),
            )
          : null,
    ),
    body: _failed
        ? ErrorView(
            message:
                'No pudimos abrir ${widget.miniApp.title}. El servicio no responde o no tienes conexión.',
            onRetry: _load,
          )
        : WebViewWidget(controller: _controller),
  );
}
