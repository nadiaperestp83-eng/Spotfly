Future<Response> _sendRequest(
  String action,
  Map<dynamic, dynamic> data, {
  additionalParams = "",
  int retryCount = 0,
}) async {
  const maxRetries = 3;
  try {
    final response = await dio
        .post(
          "$baseUrl$action$fixedParms$additionalParams",
          options: Options(headers: _headers),
          data: data,
        )
        .timeout(const Duration(seconds: 15));

    if (response.statusCode == 200) {
      return response;
    }

    if (retryCount >= maxRetries) {
      printINFO("Max retries atingido para $action (status ${response.statusCode})");
      throw NetworkError();
    }

    await Future.delayed(Duration(milliseconds: 500 * (retryCount + 1)));
    return _sendRequest(action, data,
        additionalParams: additionalParams, retryCount: retryCount + 1);
  } on DioException catch (e) {
    printINFO("Error $e");
    throw NetworkError();
  }
}
