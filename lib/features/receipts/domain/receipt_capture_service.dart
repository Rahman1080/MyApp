import 'dart:io';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';

import '../../../shared/services/file_storage.dart';
import 'receipt_text_parser.dart';

/// Orchestrates receipt capture: pick an image, run on-device OCR, parse the
/// recognized text, and persist the image into app-private storage.
///
/// The [TextRecognizer] is injectable so the OCR step can be faked in tests;
/// image picking stays behind [ImagePicker] (not exercised in unit tests).
class ReceiptCaptureService {
  ReceiptCaptureService({
    ImagePicker? imagePicker,
    TextRecognizer? textRecognizer,
    FileStorage? fileStorage,
  })  : _imagePicker = imagePicker ?? ImagePicker(),
        _textRecognizer =
            textRecognizer ?? TextRecognizer(script: TextRecognitionScript.latin),
        _fileStorage = fileStorage ?? FileStorage();

  final ImagePicker _imagePicker;
  final TextRecognizer _textRecognizer;
  final FileStorage _fileStorage;

  /// Lets the user pick a receipt image. Returns null when cancelled.
  Future<File?> pickImage({required ImageSource source}) async {
    final picked = await _imagePicker.pickImage(
      source: source,
      // Cap resolution: enough for OCR, keeps storage small.
      maxWidth: 2048,
      imageQuality: 85,
    );
    if (picked == null) return null;
    return File(picked.path);
  }

  /// Runs on-device text recognition on [image] and parses the result.
  ///
  /// Returns the raw recognized text plus the heuristic parse. The caller
  /// must present both to the user for confirmation — never persist blindly.
  Future<({String rawText, ParsedReceipt parsed})> recognizeAndParse(
    File image,
  ) async {
    final recognized =
        await _textRecognizer.processImage(InputImage.fromFilePath(image.path));
    final rawText = recognized.text;
    return (rawText: rawText, parsed: parseReceiptText(rawText));
  }

  /// Copies the receipt image into app-private storage. Call only after the
  /// user confirms the receipt.
  Future<File> persistImage(File image) => _fileStorage.saveReceiptImage(image);

  /// Releases the native text recognizer.
  Future<void> dispose() => _textRecognizer.close();
}
