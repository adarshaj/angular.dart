part of angular;

class UrlRewriter {
  String call(url) => url;
}

class HttpBackend {
  async.Future request(String url,
      {String method, bool withCredentials, String responseType,
      String mimeType, Map<String, String> requestHeaders, sendData,
      void onProgress(dom.ProgressEvent e)}) =>
    dom.HttpRequest.request(url,
        method: method,
        withCredentials: withCredentials,
        responseType: responseType,
        mimeType: mimeType,
        requestHeaders: requestHeaders,
        sendData: sendData,
        onProgress: onProgress);
}

class HttpResponse {
  int status;
  String responseText;
  Map<String, String> headers;
  HttpResponse([this.status, this.responseText, this.headers]);

  toString() => 'HTTP $status: $responseText';
}

/**
 * Wrapper around the browser XHR. Use Http service to fetch data
 * from the server.
 */
class Http {
  Map<String, async.Future<String>> _pendingRequests = <String, async.Future<String>>{};
  UrlRewriter _rewriter;
  HttpBackend _backend;

  Http(UrlRewriter this._rewriter, HttpBackend this._backend);

  async.Future<String> getString(String url,
      {bool withCredentials, void onProgress(dom.ProgressEvent e), Cache cache}) {
    return request(url,
        withCredentials: withCredentials,
        onProgress: onProgress,
        cache: cache).then((HttpResponse xhr) => xhr.responseText);
  }

  async.Future<HttpResponse> request(String rawUrl,
      { String method: 'GET',
        bool withCredentials: false,
        String responseType,
        String mimeType,
        Map<String, String> requestHeaders,
        sendData,
        void onProgress(dom.ProgressEvent e),
        Cache<HttpResponse> cache }) {
    String url = _rewriter(rawUrl);

    // We return a pending request only if caching is enabled.
    if (cache != null && _pendingRequests.containsKey(url)) {
      return _pendingRequests[url];
    }
    var cachedValue = (cache != null && method == 'GET') ? cache.get(url) : null;
    if (cachedValue != null) {
      return new async.Future.value(cachedValue);
    }
    var result = _backend.request(url,
        method: method,
        withCredentials: withCredentials,
        responseType: responseType,
        mimeType: mimeType,
        requestHeaders: requestHeaders,
        sendData: sendData,
        onProgress: onProgress).then((value) {
      // NOTE(deboer): Missing headers.  Ask the Dart team for a sane API.
      var response = new HttpResponse(value.status, value.responseText);

      if (cache != null) {
        cache.put(url, response);
      }
      _pendingRequests.remove(url);
      return response;
    }, onError: (HttpRequestProgressEvent event) {
      _pendingRequests.remove(url);
      HttpRequest request = event.currentTarget;
      return new async.Future.error(
          new HttpResponse(request.status, request.response));
    });
    _pendingRequests[url] = result;
    return result;
  }
}

