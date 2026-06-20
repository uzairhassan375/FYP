import 'package:camera/camera.dart';

enum ReportEvidenceKind { video, image }

/// Photo or short video attached to a manual violation report.
class ReportEvidence {
  ReportEvidence._({
    required this.kind,
    required this.file,
    this.durationSeconds,
  });

  factory ReportEvidence.video(XFile file, int durationSeconds) {
    return ReportEvidence._(
      kind: ReportEvidenceKind.video,
      file: file,
      durationSeconds: durationSeconds,
    );
  }

  factory ReportEvidence.image(XFile file) {
    return ReportEvidence._(
      kind: ReportEvidenceKind.image,
      file: file,
    );
  }

  final ReportEvidenceKind kind;
  final XFile file;

  /// Seconds of recording; only for [ReportEvidenceKind.video].
  final int? durationSeconds;
}
