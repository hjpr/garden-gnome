import 'package:flutter/foundation.dart';

import '../domain/document.dart';
import 'document_session.dart';

/// The open farm, as the growing tools see it: they read its climate and
/// plantings and change them through [changeFarm], which goes through the
/// same history and unsaved-changes tracking as an edit in Build.
abstract interface class FarmAccess implements Listenable {
  GardenDocument get farm;
  String get farmName;

  /// Whether the farm has changes that are not saved yet.
  bool get farmUnsaved;

  /// Stays the same while one farm is open, through Save as; changes when
  /// another farm is opened or a new one started.
  Object get farmIdentity;

  /// Applies [change] to the farm as one Undo step named [label]. [change]
  /// receives the farm with every ID counter raised, so new IDs are fresh.
  void changeFarm(
    String label,
    GardenDocument Function(GardenDocument farm) change,
  );
}

/// The farm open in Build. Follows the session as farms are opened.
class SessionFarm extends ChangeNotifier implements FarmAccess {
  SessionFarm(this.session) {
    session.addListener(_follow);
    _follow();
  }

  final DocumentSession session;
  Listenable? _editor;

  void _follow() {
    _editor?.removeListener(notifyListeners);
    _editor = session.editor..addListener(notifyListeners);
    notifyListeners();
  }

  @override
  GardenDocument get farm => session.editor.document;

  @override
  String get farmName => session.editor.title;

  @override
  bool get farmUnsaved => session.hasUnsavedWork;

  @override
  Object get farmIdentity => session.editor;

  @override
  void changeFarm(
    String label,
    GardenDocument Function(GardenDocument farm) change,
  ) {
    final editor = session.editor;
    editor.commit(label, change(editor.documentForEditing));
  }

  @override
  void dispose() {
    session.removeListener(_follow);
    _editor?.removeListener(notifyListeners);
    super.dispose();
  }
}

/// A farm held only in memory, for a growing tool used without Build
/// (tests and previews).
class DetachedFarm extends ChangeNotifier implements FarmAccess {
  DetachedFarm([GardenDocument? farm])
    : _farm = farm ?? GardenDocument(id: 'farm');

  GardenDocument _farm;

  @override
  GardenDocument get farm => _farm;

  @override
  String get farmName => 'Farm';

  @override
  bool get farmUnsaved => false;

  @override
  Object get farmIdentity => this;

  @override
  void changeFarm(
    String label,
    GardenDocument Function(GardenDocument farm) change,
  ) {
    _farm = change(_farm);
    notifyListeners();
  }
}
