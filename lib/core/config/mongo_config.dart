class MongoConfig {
  final String host;
  final int port;
  final String database;

  const MongoConfig({
    this.host = '127.0.0.1',
    this.port = 27017,
    this.database = 'apil',
  });

  String get connectionString => 'mongodb://$host:$port/$database';

  MongoConfig copyWith({String? host, int? port, String? database}) {
    return MongoConfig(
      host: host ?? this.host,
      port: port ?? this.port,
      database: database ?? this.database,
    );
  }
}
