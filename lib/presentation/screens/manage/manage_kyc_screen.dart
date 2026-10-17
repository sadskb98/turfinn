import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/sources/remote/manage_remote_source.dart';

class ManageKycScreen extends ConsumerStatefulWidget {
  final Map<String, dynamic>? existing;
  const ManageKycScreen({super.key, this.existing});

  @override
  ConsumerState<ManageKycScreen> createState() => _ManageKycScreenState();
}

class _ManageKycScreenState extends ConsumerState<ManageKycScreen> {
  late final TextEditingController _businessName;
  late final TextEditingController _nidNumber;
  late final TextEditingController _payout;

  String? _nidFrontUrl;
  String? _nidBackUrl;
  String? _selfieUrl;
  bool _submitting = false;
  String? _error;
  String? _rejectionNote;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _businessName = TextEditingController(text: e?['business_name'] ?? '');
    _nidNumber = TextEditingController(text: e?['nid_number'] ?? '');
    _payout = TextEditingController(text: e?['payout_account'] ?? '');
    _nidFrontUrl = e?['nid_photo_front_url'];
    _nidBackUrl = e?['nid_photo_back_url'];
    _selfieUrl = e?['selfie_url'];
    if (e?['status'] == 'rejected') {
      _rejectionNote = e?['review_note'] as String?;
    }
  }

  @override
  void dispose() {
    _businessName.dispose();
    _nidNumber.dispose();
    _payout.dispose();
    super.dispose();
  }

  Future<String?> _pickAndUpload(String label, String bucket) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return null;
    final file = result.files.first;
    final bytes = file.bytes;
    if (bytes == null) return null;
    final ext = file.extension ?? 'jpg';
    final contentType = 'image/$ext';
    final src = ref.read(manageRemoteSourceProvider);
    final presign = await src.presignUpload(
        bucket, '${label.toLowerCase().replaceAll(' ', '_')}_${DateTime.now().millisecondsSinceEpoch}.$ext');
    await src.uploadToPresignUrl(presign['url'] as String, bytes, contentType);
    return presign['public_url'] as String;
  }

  Future<void> _submit() async {
    if (_businessName.text.isEmpty || _nidNumber.text.isEmpty || _payout.text.isEmpty) {
      setState(() => _error = 'All fields are required.');
      return;
    }
    if (_nidFrontUrl == null || _nidBackUrl == null || _selfieUrl == null) {
      setState(() => _error = 'Please upload all required photos.');
      return;
    }
    setState(() { _submitting = true; _error = null; });
    try {
      await ref.read(manageRemoteSourceProvider).submitKyc({
        'business_name': _businessName.text,
        'nid_number': _nidNumber.text,
        'nid_photo_front_url': _nidFrontUrl,
        'nid_photo_back_url': _nidBackUrl,
        'selfie_url': _selfieUrl,
        'payout_account': _payout.text,
      });
      if (mounted) context.go('/kyc-pending');
    } catch (e) {
      setState(() => _error = 'Submission failed. Please try again.');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Verify Your Business', style: GoogleFonts.nunito(
                  fontSize: 26, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
                const SizedBox(height: 4),
                Text('Complete KYC to access your dashboard', style: GoogleFonts.dmSans(
                  fontSize: 14, color: AppColors.textSecondary)),
                if (_rejectionNote != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.redAccent.withValues(alpha: 0.4)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Previous application rejected', style: GoogleFonts.dmSans(
                          fontSize: 13, fontWeight: FontWeight.w700, color: Colors.redAccent)),
                        const SizedBox(height: 4),
                        Text(_rejectionNote!, style: GoogleFonts.dmSans(
                          fontSize: 13, color: AppColors.textSecondary)),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                _textField('Business name *', _businessName),
                const SizedBox(height: 14),
                _textField('NID number *', _nidNumber),
                const SizedBox(height: 14),
                _textField('bKash / payout account *', _payout),
                const SizedBox(height: 24),
                Text('Documents', style: GoogleFonts.dmSans(
                  fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
                const SizedBox(height: 12),
                _ImagePickerField(
                  label: 'NID Front *',
                  currentUrl: _nidFrontUrl,
                  onPick: () async {
                    final url = await _pickAndUpload('nid_front', 'kyc-documents');
                    if (url != null) setState(() => _nidFrontUrl = url);
                  },
                ),
                const SizedBox(height: 12),
                _ImagePickerField(
                  label: 'NID Back *',
                  currentUrl: _nidBackUrl,
                  onPick: () async {
                    final url = await _pickAndUpload('nid_back', 'kyc-documents');
                    if (url != null) setState(() => _nidBackUrl = url);
                  },
                ),
                const SizedBox(height: 12),
                _ImagePickerField(
                  label: 'Selfie *',
                  currentUrl: _selfieUrl,
                  onPick: () async {
                    final url = await _pickAndUpload('selfie', 'kyc-documents');
                    if (url != null) setState(() => _selfieUrl = url);
                  },
                ),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Text(_error!, style: GoogleFonts.dmSans(fontSize: 13, color: Colors.redAccent)),
                ],
                const SizedBox(height: 28),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: AppColors.black,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: _submitting ? null : _submit,
                    child: _submitting
                        ? const SizedBox(width: 20, height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.black))
                        : Text('Submit Application', style: GoogleFonts.dmSans(
                            fontSize: 15, fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _textField(String label, TextEditingController ctrl) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: GoogleFonts.dmSans(fontSize: 13, color: AppColors.textSecondary)),
        const SizedBox(height: 6),
        TextField(
          controller: ctrl,
          style: GoogleFonts.dmSans(fontSize: 15, color: AppColors.textPrimary),
          decoration: InputDecoration(
            filled: true,
            fillColor: AppColors.surfaceDark,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppColors.primaryDeep),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppColors.primaryDeep),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          ),
        ),
      ],
    );
  }
}

class _ImagePickerField extends StatelessWidget {
  const _ImagePickerField({
    required this.label,
    required this.currentUrl,
    required this.onPick,
  });

  final String label;
  final String? currentUrl;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPick,
      child: Container(
        height: 72,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: AppColors.surfaceDark,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: currentUrl != null ? AppColors.primary : AppColors.primaryDeep,
          ),
        ),
        child: Row(
          children: [
            Icon(
              currentUrl != null ? Icons.check_circle : Icons.upload_file,
              color: currentUrl != null ? AppColors.primary : AppColors.textSecondary,
              size: 22,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                currentUrl != null ? '$label — uploaded ✓' : 'Tap to upload $label',
                style: GoogleFonts.dmSans(
                  fontSize: 14,
                  color: currentUrl != null ? AppColors.primary : AppColors.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
