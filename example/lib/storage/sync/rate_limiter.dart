import 'dart:async';

/// Rate limiter for API requests (60 requests per minute)
class RateLimiter {
  final int maxRequests;
  final Duration window;

  final List<DateTime> _requestTimes = [];
  DateTime? _resetTime;

  RateLimiter({
    this.maxRequests = 60,
    this.window = const Duration(minutes: 1),
  });

  /// Check if we can make a request now
  bool canRequest() {
    final now = DateTime.now();

    // Remove requests outside the window
    _requestTimes.removeWhere((time) => now.difference(time) > window);

    return _requestTimes.length < maxRequests;
  }

  /// Record a request
  void recordRequest() {
    final now = DateTime.now();
    _requestTimes.add(now);

    // Calculate next reset time
    if (_requestTimes.isNotEmpty) {
      _resetTime = _requestTimes.first.add(window);
    }
  }

  /// Get time until next request is allowed
  Duration? timeUntilNextRequest() {
    if (canRequest()) return Duration.zero;

    if (_requestTimes.isEmpty || _resetTime == null) {
      return null;
    }

    final now = DateTime.now();
    final waitTime = _resetTime!.difference(now);

    return waitTime.isNegative ? Duration.zero : waitTime;
  }

  /// Wait until a request can be made
  Future<void> waitIfNeeded() async {
    if (canRequest()) return;

    final waitTime = timeUntilNextRequest();
    if (waitTime != null && waitTime.inMilliseconds > 0) {
      await Future.delayed(waitTime);
    }
  }

  /// Get current rate limit status
  Map<String, dynamic> getStatus() {
    return {
      'remaining': maxRequests - _requestTimes.length,
      'limit': maxRequests,
      'resetAt': _resetTime?.toIso8601String(),
    };
  }
}
