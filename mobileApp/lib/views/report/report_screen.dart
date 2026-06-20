import 'package:camera/camera.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/env.dart';
import '../../core/student_session.dart';
import '../../models/report_evidence.dart';
import '../../services/manual_violation_service.dart';
import '../../widgets/shared/custom_button.dart';
import '../../widgets/shared/custom_input_field.dart';
import 'widgets/short_video_record_page.dart';

class ReportScreen extends StatefulWidget {
  const ReportScreen({super.key, this.onReportSubmitted});

  /// When this screen is embedded in the home tab, call this after a successful submit
  /// so the Home tab can refresh live stats (no route to pop).
  final VoidCallback? onReportSubmitted;

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  final _formKey = GlobalKey<FormState>();
  final _descriptionController = TextEditingController();
  final _locationController = TextEditingController();
  final _studentNameController = TextEditingController();
  final _sapIdController = TextEditingController();
  final _departmentController = TextEditingController();

  String? _selectedCategory;
  bool _showOptionalFields = false;
  ReportEvidence? _evidence;
  bool _submitting = false;

  static const int _maxVideoSeconds = 10;

  final List<String> _categories = [
    'Gun detected',
    'Knife detected',
    'Improper uniform',
    'Fighting',
    'Other',
  ];

  @override
  void dispose() {
    _descriptionController.dispose();
    _locationController.dispose();
    _studentNameController.dispose();
    _sapIdController.dispose();
    _departmentController.dispose();
    super.dispose();
  }

  Future<void> _openVideoRecorder() async {
    final clip = await Navigator.of(context).push<RecordedClip>(
      MaterialPageRoute(
        builder: (_) => const ShortVideoRecordPage(maxSeconds: _maxVideoSeconds),
      ),
    );
    if (!mounted || clip == null) return;
    setState(() => _evidence = ReportEvidence.video(clip.file, clip.durationSeconds));
  }

  Future<void> _pickVideoFromDevice() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.video,
      allowMultiple: false,
      withData: true,
    );
    if (!mounted || result == null || result.files.isEmpty) return;

    final picked = result.files.single;
    final XFile file;
    if (picked.bytes != null) {
      file = XFile.fromData(
        picked.bytes!,
        name: picked.name.isNotEmpty ? picked.name : 'upload.mp4',
        mimeType: 'video/mp4',
      );
    } else if (picked.path != null && picked.path!.isNotEmpty) {
      file = XFile(picked.path!, name: picked.name);
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not read the selected video file.')),
      );
      return;
    }

    setState(() => _evidence = ReportEvidence.video(file, 0));
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    if (_evidence == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please record or upload a video for evidence.'),
        ),
      );
      return;
    }

    if (StudentSession.instance.user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You must be signed in as a student to submit a report.')),
      );
      return;
    }

    if (!Env.hasSupabaseConfig) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Supabase is not configured in assets/env/flutter.env.')),
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      final service = ManualViolationService(Supabase.instance.client);
      await service.submit(
        evidence: _evidence!,
        category: _selectedCategory!,
        description: _descriptionController.text.trim(),
        location: _locationController.text.trim(),
        subjectStudentName: _studentNameController.text.trim(),
        subjectSapId: _sapIdController.text.trim(),
        subjectDepartment: _departmentController.text.trim(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Report submitted. HawkEye AI is checking the evidence — if confirmed, the violator is fined and you earn 500 reward points.',
          ),
        ),
      );
      _resetAfterSubmit();
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop(true);
      } else {
        widget.onReportSubmitted?.call();
      }
    } on PostgrestException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    } on StorageException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Submit failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _resetAfterSubmit() {
    _descriptionController.clear();
    _locationController.clear();
    _studentNameController.clear();
    _sapIdController.clear();
    _departmentController.clear();
    setState(() {
      _selectedCategory = null;
      _evidence = null;
      _showOptionalFields = false;
    });
  }

  String _evidenceSummary() {
    final e = _evidence;
    if (e == null) return 'No video yet';
    if (e.durationSeconds != null && e.durationSeconds! > 0) {
      return 'Video ready (${e.durationSeconds}s)';
    }
    return 'Video uploaded';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: const Text(
          'Submit Report',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Color(0xFF333333),
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Color(0xFF333333)),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Evidence (video)',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF333333),
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE0E0E0), width: 2),
                  ),
                  child: Column(
                    children: [
                      Icon(
                        _evidence != null ? Icons.check_circle : Icons.videocam_outlined,
                        size: 40,
                        color: _evidence != null ? const Color(0xFF4CAF50) : const Color(0xFF999999),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _evidenceSummary(),
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF333333),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Record up to $_maxVideoSeconds seconds, or upload a video from your device.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _submitting ? null : _openVideoRecorder,
                              icon: const Icon(Icons.videocam),
                              label: const Text('Record video'),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                side: const BorderSide(color: Color(0xFF2196F3)),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _submitting ? null : _pickVideoFromDevice,
                              icon: const Icon(Icons.upload_file),
                              label: const Text('Upload video'),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                side: const BorderSide(color: Color(0xFF2196F3)),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Text(
                          'Category',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF333333),
                          ),
                        ),
                        Text(' *', style: TextStyle(color: Colors.red)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      key: ValueKey(_selectedCategory),
                      initialValue: _selectedCategory,
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Color(0xFF2196F3), width: 2),
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                      ),
                      hint: const Text('Select violation type'),
                      items: _categories.map((category) {
                        return DropdownMenuItem(
                          value: category,
                          child: Text(category),
                        );
                      }).toList(),
                      onChanged: (value) {
                        setState(() {
                          _selectedCategory = value;
                        });
                      },
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please select a category';
                        }
                        return null;
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                CustomInputField(
                  label: 'Description',
                  placeholder: 'Describe what happened...',
                  prefixIcon: Icons.description,
                  controller: _descriptionController,
                  isRequired: true,
                  keyboardType: TextInputType.multiline,
                  maxLines: 5,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter a description';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 20),
                CustomInputField(
                  label: 'Location',
                  placeholder: 'e.g., Building A, Room 101',
                  prefixIcon: Icons.location_on,
                  controller: _locationController,
                ),
                const SizedBox(height: 24),
                GestureDetector(
                  onTap: () {
                    setState(() {
                      _showOptionalFields = !_showOptionalFields;
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Student Details (Optional)',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF333333),
                          ),
                        ),
                        Icon(
                          _showOptionalFields ? Icons.expand_less : Icons.expand_more,
                          color: const Color(0xFF333333),
                        ),
                      ],
                    ),
                  ),
                ),
                if (_showOptionalFields) ...[
                  const SizedBox(height: 16),
                  CustomInputField(
                    label: 'Student Name',
                    placeholder: 'If known',
                    prefixIcon: Icons.person,
                    controller: _studentNameController,
                  ),
                  const SizedBox(height: 20),
                  CustomInputField(
                    label: 'SAP ID',
                    placeholder: 'SAP123456',
                    prefixIcon: Icons.badge,
                    controller: _sapIdController,
                  ),
                  const SizedBox(height: 20),
                  CustomInputField(
                    label: 'Department',
                    placeholder: 'CS, ECE...',
                    prefixIcon: Icons.school,
                    controller: _departmentController,
                  ),
                ],
                const SizedBox(height: 32),
                CustomButton(
                  text: _submitting ? 'Submitting…' : 'Submit Report',
                  icon: Icons.send,
                  onPressed: _submitting ? null : _submit,
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
