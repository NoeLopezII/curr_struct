class Logger {
  final List<String> _logs = [];

  List<String> get logs => _logs;

  void addLog(String message) {
    final timestamp = DateTime.now().toString().substring(11, 19);
    _logs.add('[$timestamp] $message');
    //print('[APP LOG] $message'); // Add this line to print to console
    if (_logs.length > 100) _logs.removeAt(0);
  }
}