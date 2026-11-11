import 'dart:typed_data';

import 'package:crop_your_image/crop_your_image.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../app/theme.dart';
import '../../data/models.dart';
import '../../widgets/common.dart';
import 'sticker_service.dart';
import 'sticker_widgets.dart';

enum _Shape { square, rounded, circle }

/// Photo -> crop -> shape + captions -> 512x512 WebP sticker.
class ImageStickerEditor extends StatefulWidget {
  const ImageStickerEditor({super.key, required this.pack, required this.service});

  final StickerPack pack;
  final StickerService service;

  @override
  State<ImageStickerEditor> createState() => _ImageStickerEditorState();
}

class _ImageStickerEditorState extends State<ImageStickerEditor> {
  final _crop = CropController();
  final _canvasKey = GlobalKey();
  final _busy = ValueNotifier<String?>(null);

  Uint8List? _source;
  Uint8List? _cropped;
  _Shape _shape = _Shape.rounded;
  bool _outline = true;
  String _emoji = '😀';
  final List<StickerText> _texts = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _pick());
  }

  @override
  void dispose() {
    _busy.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final file = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 2048, maxHeight: 2048);
    if (file == null) {
      if (mounted && _source == null) Navigator.pop(context);
      return;
    }
    final bytes = await file.readAsBytes();
    setState(() {
      _source = bytes;
      _cropped = null;
    });
  }

  Future<void> _save() async {
    _busy.value = 'Creando sticker…';
    try {
      final png = await captureBoundary512(_canvasKey);
      await widget.service.addStaticSticker(widget.pack, png, _emoji);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showToast(context, '$e');
    } finally {
      _busy.value = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cropping = _source != null && _cropped == null;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(CupertinoIcons.xmark), onPressed: () => Navigator.pop(context)),
        title: Text(_source == null ? 'Elige una foto' : (cropping ? 'Recortar' : 'Personalizar')),
        actions: [
          if (cropping)
            TextButton(
              onPressed: () => _crop.crop(),
              child: const Text('Siguiente', style: TextStyle(fontWeight: FontWeight.w700)),
            )
          else if (_cropped != null)
            TextButton(
              onPressed: _save,
              child: const Text('Guardar', style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.accent)),
            ),
        ],
      ),
      body: Stack(
        children: [
          if (_source == null)
            const Center(child: CupertinoActivityIndicator())
          else if (cropping)
            _buildCrop()
          else
            _buildCompose(),
          BusyOverlay(status: _busy),
        ],
      ),
    );
  }

  Widget _buildCrop() {
    return Column(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Crop(
                image: _source!,
                controller: _crop,
                aspectRatio: 1,
                interactive: true,
                baseColor: AppColors.background,
                maskColor: Colors.white.withValues(alpha: 0.7),
                radius: 16,
                progressIndicator: const CupertinoActivityIndicator(),
                onCropped: (result) {
                  switch (result) {
                    case CropSuccess(:final croppedImage):
                      setState(() => _cropped = croppedImage);
                    case CropFailure(:final cause):
                      showToast(context, 'No se pudo recortar: $cause');
                  }
                },
              ),
            ),
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.paddingOf(context).bottom + 16),
          child: Row(
            children: [
              TextButton.icon(
                onPressed: _pick,
                icon: const Icon(CupertinoIcons.photo),
                label: const Text('Otra foto'),
              ),
              const Spacer(),
              const Text('Pellizca para hacer zoom', style: TextStyle(color: AppColors.inkSecondary, fontSize: 12)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCompose() {
    Widget image = Image.memory(_cropped!, fit: BoxFit.cover);
    image = switch (_shape) {
      _Shape.square => image,
      _Shape.rounded => ClipRRect(borderRadius: BorderRadius.circular(64), child: image),
      _Shape.circle => ClipOval(child: image),
    };
    if (_outline && _shape != _Shape.square) {
      final radius = _shape == _Shape.circle ? null : BorderRadius.circular(72);
      image = Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white,
          shape: _shape == _Shape.circle ? BoxShape.circle : BoxShape.rectangle,
          borderRadius: radius,
        ),
        child: image,
      );
    }

    return ListView(
      padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom + 24),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: AspectRatio(
                aspectRatio: 1,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      const Checkerboard(),
                      // Everything inside this boundary is exported (transparent background).
                      RepaintBoundary(
                        key: _canvasKey,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            Padding(padding: const EdgeInsets.all(14), child: image),
                            StickerTextLayer(
                              items: _texts,
                              onChanged: () {},
                              onTapItem: (t) async {
                                await editStickerText(context, existing: t);
                                setState(() {
                                  if (t.text.trim().isEmpty) _texts.remove(t);
                                });
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        const _SectionLabel('Forma'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: CupertinoSlidingSegmentedControl<_Shape>(
            groupValue: _shape,
            onValueChanged: (v) => setState(() => _shape = v ?? _Shape.rounded),
            children: const {
              _Shape.square: Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('Cuadrado')),
              _Shape.rounded: Text('Redondeado'),
              _Shape.circle: Text('Círculo'),
            },
          ),
        ),
        SwitchListTile.adaptive(
          contentPadding: const EdgeInsets.symmetric(horizontal: 20),
          title: const Text('Borde blanco de sticker'),
          value: _outline,
          activeThumbColor: AppColors.accent,
          onChanged: _shape == _Shape.square ? null : (v) => setState(() => _outline = v),
        ),
        const _SectionLabel('Texto'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: [
              FilledButton.tonalIcon(
                onPressed: () async {
                  final t = await editStickerText(context);
                  if (t != null && t.text.trim().isNotEmpty) setState(() => _texts.add(t));
                },
                icon: const Icon(CupertinoIcons.textformat),
                label: const Text('Añadir texto'),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Arrastra para mover, pellizca para escalar, toca para editar.',
                  style: TextStyle(color: AppColors.inkSecondary, fontSize: 12),
                ),
              ),
            ],
          ),
        ),
        const _SectionLabel('Emoji (lo usa WhatsApp para sugerirlo)'),
        EmojiPicker(selected: _emoji, onSelected: (e) => setState(() => _emoji = e)),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
    child: Text(
      text.toUpperCase(),
      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.5, color: AppColors.inkSecondary),
    ),
  );
}
