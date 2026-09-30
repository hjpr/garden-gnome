import 'package:uuid/uuid.dart';

const _uuid = Uuid();

String newUuid() => _uuid.v4();
