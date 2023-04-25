import 'dart:async';
import 'package:dio/dio.dart';
import 'package:signalr_netcore/ihub_protocol.dart';
import 'errors.dart';
import 'signalr_http_client.dart';
import 'utils.dart';
import 'package:logging/logging.dart';

typedef OnHttpClientCreateCallback = void Function(Dio httpClient);

class WebSupportingHttpClient extends SignalRHttpClient {
  // Properties

  final Dio _httpClient;
  final Logger? _logger;
  final OnHttpClientCreateCallback? _httpClientCreateCallback;

  // Methods

  WebSupportingHttpClient(Dio httpClient, Logger? logger,
      {OnHttpClientCreateCallback? httpClientCreateCallback})
      : this._httpClient = httpClient,
        this._logger = logger,
        this._httpClientCreateCallback = httpClientCreateCallback;

  Future<SignalRHttpResponse> send(SignalRHttpRequest request) {
    // Check that abort was not signaled before calling send
    if ((request.abortSignal != null) && request.abortSignal!.aborted!) {
      return Future.error(AbortError());
    }

    if ((request.method == null) || (request.method!.length == 0)) {
      return Future.error(new ArgumentError("No method defined."));
    }

    if ((request.url == null) || (request.url!.length == 0)) {
      return Future.error(new ArgumentError("No url defined."));
    }

    return Future<SignalRHttpResponse>(() async {
      final uri = Uri.parse(request.url!);

      // if (_httpClientCreateCallback != null) {
      //   _httpClientCreateCallback!(httpClient);
      // }

      final abortFuture = Future<void>(() {
        final completer = Completer<void>();
        if (request.abortSignal != null) {
          request.abortSignal!.onabort = () {
            if (!completer.isCompleted) completer.completeError(AbortError());
          };
        }
        return completer.future;
      });

      final isJson = request.content != null &&
          request.content is String &&
          (request.content as String).startsWith('{');

      var headers = MessageHeaders();

      headers.setHeaderValue('X-Requested-With', 'FlutterHttpClient');
      headers.setHeaderValue(
          'content-type',
          isJson
              ? 'application/json;charset=UTF-8'
              : 'text/plain;charset=UTF-8');

      headers.addMessageHeaders(request.headers);

      _logger?.finest(
          "HTTP send: url '${request.url}', method: '${request.method}' content: '${request.content}' content length = '${(request.content as String).length}' headers: '$headers'");

      final httpRespFuture = await Future.any(
          [_sendHttpRequest(_httpClient, request, uri, headers), abortFuture]);
      final httpResp = httpRespFuture as Response;

      if (request.abortSignal != null) {
        request.abortSignal!.onabort = null;
      }

      if ((httpResp.statusCode! >= 200) && (httpResp.statusCode! < 300)) {
        Object content;
        final contentTypeHeader = httpResp.headers.value('content-type');
        final isJsonContent = contentTypeHeader == null ||
            contentTypeHeader.startsWith('application/json');
        if (isJsonContent) {
          content = httpResp.data;
        } else {
          content = httpResp.data;
          // When using SSE and the uri has an 'id' query parameter the response is not evaluated, otherwise it is an error.
          if (isStringEmpty(uri.queryParameters['id'])) {
            throw ArgumentError(
                "Response Content-Type not supported: $contentTypeHeader");
          }
        }

        return SignalRHttpResponse(httpResp.statusCode!,
            statusText: httpResp.statusMessage, content: content);
      } else {
        throw HttpError(httpResp.statusMessage, httpResp.statusCode!);
      }
    });
  }

  Future<Response> _sendHttpRequest(
    Dio httpClient,
    SignalRHttpRequest request,
    Uri uri,
    MessageHeaders headers,
  ) {
    Future<Response> httpResponse;
    Options options = Options(
      headers: headers.asMap
    );
    switch (request.method!.toLowerCase()) {
      case 'post':
        httpResponse =
            httpClient.post(uri.toString(), data: request.content, options: options);
        break;
      case 'put':
        httpResponse =
            httpClient.put(uri.toString(), data: request.content, options: options);
        break;
      case 'delete':
        httpResponse = httpClient.delete(uri.toString(),
            data: request.content, options: options);
        break;
      case 'get':
      default:
        httpResponse = httpClient.get(uri.toString(), options: options);
    }

    final hasTimeout = (request.timeout != null) && (0 < request.timeout!);
    if (hasTimeout) {
      httpResponse =
          httpResponse.timeout(Duration(milliseconds: request.timeout!));
    }

    return httpResponse;
  }
}
