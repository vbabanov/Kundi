import 'package:dio/dio.dart';

import 'anti_bot/browser_like_client.dart';
import 'contracts/diary_connector.dart';
import 'diagnostics/connector_diagnostics.dart';
import 'mappers/canonical_bundle_mapper.dart';
import 'raw_payload/raw_payload_repository.dart';
import 'session/connector_session_store.dart';
import 'source_adapters/dnevnikru/dnevnikru_connector.dart';
import 'source_adapters/edupage/edupage_connector.dart';
import 'source_adapters/kundelik/kundelik_connector.dart';

class ConnectorRuntime {
  ConnectorRuntime({DiaryConnector Function(String source)? connectorFactory})
      : _connectorFactory = connectorFactory,
        _sessionStore = ConnectorSessionStore(),
        _payloadRepository = RawPayloadRepository(),
        _diagnostics = ConnectorDiagnostics(),
        _mapper = const CanonicalBundleMapper(),
        _client = BrowserLikeClient(
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 20),
              receiveTimeout: const Duration(seconds: 30),
              sendTimeout: const Duration(seconds: 30),
              followRedirects: true,
              validateStatus: (_) => true,
            ),
          ),
        );

  final DiaryConnector Function(String source)? _connectorFactory;
  final ConnectorSessionStore _sessionStore;
  final RawPayloadRepository _payloadRepository;
  final ConnectorDiagnostics _diagnostics;
  final CanonicalBundleMapper _mapper;
  final BrowserLikeClient _client;

  DiaryConnector create(String source) {
    final injectedFactory = _connectorFactory;
    if (injectedFactory != null) {
      return injectedFactory(source);
    }
    switch (source.trim().toLowerCase()) {
      case 'kundelik':
        return KundelikConnector(
          client: _client,
          sessionStore: _sessionStore,
          rawPayloadRepository: _payloadRepository,
          diagnostics: _diagnostics,
          mapper: _mapper,
        );
      case 'dnevnikru':
        return DnevnikRuConnector();
      case 'edupage':
        return EduPageConnector();
      default:
        throw ArgumentError.value(source, 'source', 'unsupported source');
    }
  }

  List<String> exportDiagnostics() => _diagnostics.export();
}
