import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../application/editor_controller.dart';
import '../../domain/reference_image.dart';
import '../canvas/reference_image_cache.dart';
import '../theme.dart';
import '../widgets/draft_text_field.dart';
import '../widgets/panel.dart';

/// Properties for the Reference layer, always laid out the same way:
/// an Upload image button, the selected image's name (click to rename,
/// bin to remove), then its opacity and scale. Locking is in Layers. With no image
/// selected the name, settings and fields are shown greyed out.
class ReferenceProperties extends StatefulWidget {
  const ReferenceProperties({super.key, required this.editor});

  final EditorController editor;

  @override
  State<ReferenceProperties> createState() => _ReferencePropertiesState();
}

class _ReferencePropertiesState extends State<ReferenceProperties> {
  bool _loading = false;
  String? _error;

  EditorController get _editor => widget.editor;

  /// Picks a picture, checks it, and adds it on top of the Reference
  /// layer. Cancelling the picker, or a picture that cannot be used,
  /// changes nothing.
  Future<void> _upload() async {
    const group = XTypeGroup(
      label: 'Images',
      extensions: ['png', 'jpg', 'jpeg', 'webp'],
      mimeTypes: ['image/png', 'image/jpeg', 'image/webp'],
    );
    final file = await openFile(acceptedTypeGroups: [group]);
    if (file == null || !mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    final editor = _editor;
    final document = editor.document;
    String? problem;
    try {
      final bytes = await file.readAsBytes();
      final mimeType = imageMimeType(bytes);
      if (bytes.length > maxReferenceBytes) {
        problem = 'That image is over 20 MB. Choose a smaller one';
      } else if (mimeType == null) {
        problem = 'Choose a PNG, JPEG or WebP image';
      } else {
        final size = await decodeImageSize(bytes);
        if (size == null) {
          problem = 'That image could not be read';
        } else if (size.width * size.height > maxReferencePixels) {
          problem = 'That image is over 40 megapixels. Choose a smaller one';
        } else if (!identical(editor.document, document)) {
          // The drawing changed while the file loaded (another drawing
          // opened, or an Undo); do not drop the picture into it.
          problem = 'The drawing changed while loading. Try again';
        } else {
          editor.addReferenceImage(
            fileName: file.name,
            bytes: bytes,
            mimeType: mimeType,
            pixelWidth: size.width,
            pixelHeight: size.height,
          );
        }
      }
    } catch (_) {
      problem = 'That image could not be read';
    }
    if (!mounted) return;
    setState(() {
      _loading = false;
      _error = problem;
    });
  }

  @override
  Widget build(BuildContext context) {
    final image = _editor.selectedImage;
    final editable = image != null && !image.locked;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _UploadButton(loading: _loading, onPressed: _upload),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              _error!,
              style: const TextStyle(fontSize: 12, color: Palette.invalid),
            ),
          ),
        const SizedBox(height: 8),
        _ImageName(
          key: ValueKey(('image-name', image?.id)),
          editor: _editor,
          image: image,
        ),
        PropertyGroup(
          title: 'LOOK',
          children: [
            PropertyRow(
              label: 'Opacity',
              child: _OpacitySlider(editor: _editor, image: image),
            ),
          ],
        ),
        PropertyGroup(
          title: 'SCALE',
          children: [
            PropertyRow(
              label: 'Distance (${_editor.settings.units.symbol})',
              child: _DistanceField(
                editor: _editor,
                image: image,
                enabled: editable && image.hasLine,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Full-width Upload image button, styled like a chosen drawing tool: an
/// icon over its label, raised on white.
class _UploadButton extends StatelessWidget {
  const _UploadButton({required this.loading, required this.onPressed});

  final bool loading;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    const colour = Palette.accent;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Palette.field,
        borderRadius: BorderRadius.circular(Metrics.radius + 2),
      ),
      child: Semantics(
        button: true,
        label: 'Upload image',
        excludeSemantics: true,
        child: Container(
          decoration: BoxDecoration(
            color: Palette.paper,
            borderRadius: BorderRadius.circular(Metrics.radius),
            boxShadow: const [
              BoxShadow(
                color: Color(0x1F000000),
                blurRadius: 3,
                offset: Offset(0, 1),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: loading ? null : onPressed,
              borderRadius: BorderRadius.circular(Metrics.radius),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 7),
                child: Column(
                  children: [
                    const AppIcon('add-reference.svg', size: 18, color: colour),
                    const SizedBox(height: 3),
                    Text(
                      loading ? 'Loading…' : 'Upload image',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: colour,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The selected image's name with a bin beside it. Clicking the name
/// turns it into a text box: Enter or clicking away saves, Esc cancels,
/// and a blank name goes back to the automatic one. Long names end in an
/// ellipsis. Greyed out when no image is selected.
class _ImageName extends StatefulWidget {
  const _ImageName({super.key, required this.editor, required this.image});

  final EditorController editor;
  final ReferenceImage? image;

  @override
  State<_ImageName> createState() => _ImageNameState();
}

class _ImageNameState extends State<_ImageName> {
  TextEditingController? _text;
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus && _text != null) _save();
    });
  }

  @override
  void dispose() {
    _focus.dispose();
    _text?.dispose();
    super.dispose();
  }

  void _start() {
    final image = widget.image;
    if (image == null) return;
    setState(() {
      _text = TextEditingController(text: image.displayName)
        ..selection = TextSelection(
          baseOffset: 0,
          extentOffset: image.displayName.length,
        );
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  void _save() {
    final text = _text?.text;
    final image = widget.image;
    setState(() {
      _text?.dispose();
      _text = null;
    });
    if (text == null || image == null) return;
    // Keeping the shown name as typed only makes it a custom name when it
    // differs from the automatic one.
    final automatic = image.withLabel(null).displayName;
    final label = text.trim() == automatic ? null : text;
    widget.editor.updateReference('Rename image', image.withLabel(label));
  }

  void _cancel() {
    setState(() {
      _text?.dispose();
      _text = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final image = widget.image;
    final text = _text;
    final name = image?.displayName ?? 'No image selected';
    return Container(
      height: 34,
      padding: const EdgeInsets.only(left: 8),
      decoration: BoxDecoration(
        color: Palette.field,
        borderRadius: BorderRadius.circular(Metrics.radius),
      ),
      child: Row(
        children: [
          Icon(
            Icons.photo_outlined,
            size: 14,
            color: image == null ? Palette.faint : Palette.muted,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: text != null
                ? CallbackShortcuts(
                    bindings: {
                      const SingleActivator(LogicalKeyboardKey.escape): _cancel,
                    },
                    child: TextField(
                      controller: text,
                      focusNode: _focus,
                      style: const TextStyle(fontSize: 13),
                      decoration: const InputDecoration(
                        isDense: true,
                        filled: false,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        contentPadding: EdgeInsets.zero,
                      ),
                      onSubmitted: (_) => _save(),
                    ),
                  )
                : Tooltip(
                    message: image == null ? '' : 'Click to rename',
                    child: InkWell(
                      onTap: image == null ? null : _start,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: image == null ? Palette.faint : Palette.ink,
                          ),
                        ),
                      ),
                    ),
                  ),
          ),
          IconAction(
            iconData: Icons.delete_outline,
            label: image == null ? 'Remove image' : 'Remove $name',
            size: 30,
            onPressed: image == null
                ? null
                : () => widget.editor.removeReference(image.id),
          ),
        ],
      ),
    );
  }
}

/// Opacity from 0 to 100%. Dragging shows the change live; letting go
/// saves it as one Undo step.
class _OpacitySlider extends StatelessWidget {
  const _OpacitySlider({required this.editor, required this.image});

  final EditorController editor;
  final ReferenceImage? image;

  @override
  Widget build(BuildContext context) {
    final image = this.image;
    final value = image == null ? 0.6 : editor.opacityOf(image);
    return Row(
      children: [
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
            ),
            child: Slider(
              value: value,
              semanticFormatterCallback: (v) => '${(v * 100).round()}%',
              onChanged: image == null ? null : editor.previewReferenceOpacity,
              onChangeEnd: image == null ? null : editor.setReferenceOpacity,
            ),
          ),
        ),
        SizedBox(
          width: 34,
          child: Text(
            '${(value * 100).round()}%',
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: 12,
              color: image == null ? Palette.faint : Palette.muted,
            ),
          ),
        ),
      ],
    );
  }
}

/// The real length of the reference line, in the user's units. Enter (or
/// leaving the box) scales the image so the line is that long.
class _DistanceField extends StatelessWidget {
  const _DistanceField({
    required this.editor,
    required this.image,
    required this.enabled,
  });

  final EditorController editor;
  final ReferenceImage? image;

  /// Only once the image has a reference line to measure.
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final image = this.image;
    final units = editor.settings.units;
    final known = image?.knownDistance;
    return DraftTextField(
      // Re-keyed when the line or units change, so stale typing is dropped.
      key: ValueKey((
        'distance',
        image?.id,
        image?.lineStart,
        image?.lineEnd,
        units,
      )),
      editor: editor,
      draftKey: 'reference/${image?.id}/distance',
      layerId: referenceDraftOwner,
      committedText: known == null ? '' : _format(units.fromMetres(known)),
      label: 'Distance',
      enabled: enabled,
      check: (text) {
        final value = double.tryParse(text.trim());
        if (value == null || !value.isFinite || value <= 0) {
          return 'Enter a distance above zero';
        }
        return null;
      },
      apply: (text) {
        final value = double.parse(text.trim());
        if (image != null) {
          editor.calibrateReference(image.id, units.toMetres(value));
        }
      },
    );
  }

  static String _format(double value) =>
      value.toStringAsFixed(3).replaceFirst(RegExp(r'\.?0+$'), '');
}
