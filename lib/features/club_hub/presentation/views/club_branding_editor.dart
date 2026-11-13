import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:run_track_app/core/theme/club_branding.dart';
import 'package:run_track_app/features/application/run_track_controller.dart';
import 'package:run_track_app/features/club_hub/domain/models/club_models.dart';

class ClubBrandingEditor extends StatefulWidget {
  const ClubBrandingEditor({
    required this.controller,
    required this.club,
    super.key,
  });

  final RunTrackController controller;
  final ClubMembership club;

  @override
  State<ClubBrandingEditor> createState() => _ClubBrandingEditorState();
}

class _ClubBrandingEditorState extends State<ClubBrandingEditor> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.club.clubName);
  late final _primary = _colour('primary', genericClubPrimary);
  late final _secondary = _colour('secondary', genericClubSecondary);
  late final _background = _colour('background', genericClubBackground);
  Uint8List? _logo;
  String? _error;
  bool _removeLogo = false;
  bool _busy = false;

  TextEditingController _colour(String key, String fallback) =>
      TextEditingController(text: clubColour(widget.club, key, fallback));

  @override
  void dispose() {
    for (final input in [_name, _primary, _secondary, _background]) {
      input.dispose();
    }
    super.dispose();
  }

  Future<void> _pickLogo() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final image = await openFile(
        acceptedTypeGroups: const [
          XTypeGroup(
            label: 'PNG, JPG or WebP images',
            extensions: ['png', 'jpg', 'jpeg', 'webp'],
            mimeTypes: ['image/png', 'image/jpeg', 'image/webp'],
            uniformTypeIdentifiers: [
              'public.png',
              'public.jpeg',
              'org.webmproject.webp',
            ],
          ),
        ],
      );
      if (image == null || !mounted) return;
      if (await image.length() > 5 * 1024 * 1024) {
        throw const FormatException('Choose an image under 5 MB.');
      }
      final png = await _prepareLogo(await image.readAsBytes());
      if (mounted) {
        setState(() {
          _logo = png;
          _removeLogo = false;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is FormatException
              ? error.message
              : 'This image could not be opened. Choose a PNG, JPG or WebP.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final saved = await widget.controller.mutate(
      () => widget.controller.repository.updateClubBranding(
        clubId: widget.club.clubId,
        name: _name.text.trim(),
        primary: _primary.text.trim(),
        secondary: _secondary.text.trim(),
        background: _background.text.trim(),
        logo: _logo == null ? null : base64Encode(_logo!),
        removeLogo: _removeLogo,
      ),
    );
    if (!mounted) return;
    if (saved) {
      Navigator.pop(context);
    } else {
      setState(() {
        _busy = false;
        _error =
            widget.controller.error ?? 'Unable to save branding. Try again.';
      });
    }
  }

  Widget _colourField(TextEditingController controller, String label) =>
      TextFormField(
        controller: controller,
        enabled: !_busy,
        textCapitalization: TextCapitalization.characters,
        decoration: InputDecoration(labelText: label, hintText: '#123ABC'),
        validator: (value) => isBrandColour(value?.trim() ?? '')
            ? null
            : 'Enter a six-digit hex colour, including #.',
      );

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Club branding'),
    content: SingleChildScrollView(
      child: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: _name,
              enabled: !_busy,
              maxLength: 120,
              decoration: const InputDecoration(labelText: 'Club display name'),
              validator: (value) => (value?.trim() ?? '').isEmpty
                  ? 'Enter a club display name.'
                  : null,
            ),
            _colourField(_primary, 'Primary colour'),
            _colourField(_secondary, 'Secondary colour'),
            _colourField(_background, 'Background colour'),
            const SizedBox(height: 16),
            if (_logo != null)
              Image.memory(_logo!, height: 80, width: 80, fit: BoxFit.contain),
            if (_removeLogo)
              const Text('The generic RunTrack icon will be used.'),
            OutlinedButton.icon(
              onPressed: _busy ? null : _pickLogo,
              icon: const Icon(Icons.upload_file),
              label: const Text('Upload logo'),
            ),
            TextButton(
              onPressed: _busy || _removeLogo
                  ? null
                  : () => setState(() {
                      _logo = null;
                      _removeLogo = true;
                    }),
              child: const Text('Use RunTrack icon'),
            ),
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: _busy ? null : () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _busy ? null : _save,
        child: Text(_busy ? 'Please wait…' : 'Save branding'),
      ),
    ],
  );
}

Future<Uint8List> _prepareLogo(Uint8List bytes) async {
  final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
  ui.ImageDescriptor? descriptor;
  ui.Codec? codec;
  ui.Image? image;
  try {
    descriptor = await ui.ImageDescriptor.encoded(buffer);
    if (descriptor.width * descriptor.height > 16 * 1024 * 1024) {
      throw const FormatException('Choose an image under 16 megapixels.');
    }
    // Limit the longest edge and preserve transparency and the original ratio.
    final landscape = descriptor.width >= descriptor.height;
    codec = await descriptor.instantiateCodec(
      targetWidth: landscape && descriptor.width > 320 ? 320 : null,
      targetHeight: !landscape && descriptor.height > 320 ? 320 : null,
    );
    image = (await codec.getNextFrame()).image;
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    if (png == null || png.lengthInBytes > 524288) {
      throw const FormatException('The logo is too large after processing.');
    }
    return png.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes);
  } finally {
    image?.dispose();
    codec?.dispose();
    descriptor?.dispose();
    buffer.dispose();
  }
}
