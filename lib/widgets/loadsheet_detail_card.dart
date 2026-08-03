import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../constants/app_colors.dart';
import '../models/loadsheet_model.dart';
import '../models/approval_model.dart';
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../constants/api_constants.dart';
import '../services/attendance_service.dart';

class LoadsheetDetailCard extends StatelessWidget {
  final LoadsheetModel         loadsheet;
  final List<dynamic>          sessions;
  final List<ApprovalModel>    approvals;
  final VoidCallback?          onContractUploaded;
  final bool                   showAmount;
  final bool                   showBankAccount;

  const LoadsheetDetailCard({
    super.key, required this.loadsheet,
    required this.sessions, required this.approvals,
    this.onContractUploaded,
    this.showAmount = true,
    this.showBankAccount = false,
  });

  DateTime? _parseServerTime(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    String s = raw.trim().replaceFirst(' ', 'T');
    if (!s.contains('Z') && !s.contains('+') && !s.contains('-', 10)) {
      s = '${s}Z';
    }
    return DateTime.tryParse(s)?.toLocal();
  }

  String _formatCheckinTime(String? timeStr) {
    if (timeStr == null || timeStr.isEmpty) return '--';
    try {
      final dt = _parseServerTime(timeStr);
      if (dt == null) return timeStr;
      return DateFormat('HH:mm').format(dt);
    } catch (_) {
      return timeStr;
    }
  }

  Future<void> _showAttendanceDialog(BuildContext context, dynamic session) async {
    final service = AttendanceService();
    final data = await service.getSessionAttendance(session['id']);
    if (!context.mounted) return;

    final attendanceList = data != null ? (data['attendance'] as List<dynamic>?) : null;
    
    if (!context.mounted) return;
    
    showDialog(
      context: context,
      builder: (dialogContext) => Dialog(
        child: Container(
          width: 520,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  const Icon(Icons.people_alt_rounded, color: AppColors.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Attendance for ${session['course_unit_code'] ?? session['course_unit_name']}',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.pop(dialogContext),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // Date
              Text(
                'Date: ${session['session_date']?.toString().substring(0, 10)}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              // Attendance List
              if (data == null)
                const Center(
                  child: Text('Failed to load attendance'),
                )
              else if (attendanceList == null || attendanceList.isEmpty)
                const Text('No attendance records for this session')
              else
                SizedBox(
                  height: 300,
                  child: ListView.builder(
                    itemCount: attendanceList.length,
                    itemBuilder: (_, i) {
                      final record = attendanceList[i];
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: AppColors.primary.withOpacity(0.1),
                          child: Text(
                            record['full_name']?.toString().substring(0, 1).toUpperCase() ?? '?',
                            style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold),
                          ),
                        ),
                        title: Text(record['full_name'] ?? 'Unknown'),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (record['student_number'] != null)
                              Text(record['student_number']),
                            Text(
                              'Checked in at: ${_formatCheckinTime(record['checkin_time'])}',
                              style: const TextStyle(fontSize: 11),
                            ),
                          ],
                        ),
                        trailing: const Icon(Icons.check_circle, color: AppColors.success),
                      );
                    },
                  ),
                ),
              const SizedBox(height: 16),
              // Close button
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Close'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat('#,##0', 'en_US');
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

        // Lecturer info
        _Section(title: 'Lecturer Information', children: [
          _Row('Name',         loadsheet.lecturerName),
          _Row('Lecturer ID',  loadsheet.lecturerIdCode ?? '--'),
          _Row('Email',        loadsheet.email ?? '--'),
          if (showBankAccount)
            _Row(
              'Bank Account',
              loadsheet.bankAccount != null && loadsheet.bankAccount!.isNotEmpty
                  ? loadsheet.bankAccount!
                  : '—',
            ),
          _Row('Month',        '${loadsheet.month} ${loadsheet.academicYear}'),
          _ContractSection(
            loadsheet: loadsheet,
            onUpload: onContractUploaded,
          ),
        ]),

        const SizedBox(height: 16),

        // Summary row
        Row(children: [
          _SumCard('Sessions',   '${loadsheet.totalSessions}',     AppColors.primary,   Icons.event),
          const SizedBox(width: 12),
          _SumCard('Total CH',   '${loadsheet.totalCh.toStringAsFixed(4)} hrs', AppColors.secondary, Icons.schedule),
          if (showAmount) ...[
            const SizedBox(width: 12),
            _SumCard('Amount',     'UGX ${fmt.format(loadsheet.calculatedPayment)}', AppColors.success, Icons.payments),
          ],
        ]),

        const SizedBox(height: 20),

        // Session breakdown
        _Section(title: 'Session Breakdown', children: [
          if (sessions.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(child: Text('No sessions found for this load sheet.',
                  style: TextStyle(color: Colors.black54, fontStyle: FontStyle.italic))),
            )
          else
            Table(
              columnWidths: const {
                0: FlexColumnWidth(2),
                1: FlexColumnWidth(1.5),
                2: FlexColumnWidth(0.8),
                3: FlexColumnWidth(0.8),
                4: FlexColumnWidth(0.8),
                5: FlexColumnWidth(1.5),
              },
              children: [
                TableRow(
                  decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.08)),
                  children: ['Course Unit','Date','Mode','Start','End','CH']
                      .map((h) => Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                          child: Text(h, style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 12))))
                      .toList(),
                ),
                ...sessions.map((s) {
                  // Parse time strings and convert from UTC to local timezone
                  final start = s['start_time'] != null
                      ? _parseServerTime(s['start_time']) != null
                          ? DateFormat('HH:mm').format(_parseServerTime(s['start_time'])!)
                          : '--'
                      : '--';
                  final end   = s['end_time'] != null
                      ? _parseServerTime(s['end_time']) != null
                          ? DateFormat('HH:mm').format(_parseServerTime(s['end_time'])!)
                          : '--'
                      : '--';
                  
                  // Format computed CH to 4 decimal places
                  final chValue = s['computed_ch'] != null 
                      ? (double.tryParse(s['computed_ch'].toString())?.toStringAsFixed(4) ?? '--')
                      : '--';
                  
                  return TableRow(
                    decoration: BoxDecoration(
                      border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
                    ),
                    children: [
                      // Column 0: Code & Name
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              s['course_unit_code'] ?? s['course_unit_name'] ?? '--',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppColors.textPrimary),
                            ),
                            if (s['course_unit_code'] != null && s['course_unit_name'] != null)
                              Text(
                                s['course_unit_name'],
                                style: const TextStyle(color: Colors.black54, fontSize: 10),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                          ],
                        ),
                      ),
                      // Column 1: Date
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                        child: Text(s['session_date']?.toString().substring(0, 10) ?? '--',
                            style: const TextStyle(fontSize: 12)),
                      ),
                      // Column 2: Mode
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                          decoration: BoxDecoration(
                            color: (s['mode'] == 'online' ? AppColors.primary : AppColors.secondary).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: s['mode'] == 'online' ? AppColors.primary : AppColors.secondary,
                              width: 1,
                            ),
                          ),
                          child: Text(
                            s['mode']?.toString().toUpperCase() ?? 'PHYSICAL',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              color: s['mode'] == 'online' ? AppColors.primary : AppColors.secondary,
                            ),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        ),
                      ),
                      // Column 3: Start
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                        child: Text(start, style: const TextStyle(fontSize: 12)),
                      ),
                      // Column 4: End
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                        child: Text(end, style: const TextStyle(fontSize: 12)),
                      ),
                      // Column 5: CH
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Flexible(
                              child: Text(chValue,
                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                            ),
                            SizedBox(
                              width: 32,
                              height: 32,
                              child: IconButton(
                                icon: const Icon(Icons.people_alt_rounded, color: AppColors.primary, size: 18),
                                onPressed: () => _showAttendanceDialog(context, s),
                                tooltip: 'View Attendance',
                                padding: EdgeInsets.zero,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                }),
              ],
            ),
        ]),

        const SizedBox(height: 20),

        // Approval trail
        if (approvals.isNotEmpty) ...[
          _Section(title: 'Approval Trail', children: [
            ...approvals.map((a) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(children: [
                Icon(
                  a.action == 'approved' ? Icons.check_circle : Icons.cancel,
                  color: a.action == 'approved' ? AppColors.success : AppColors.danger,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${a.officerName} (${a.role.replaceAll('_', ' ')})',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    Text('${a.action.toUpperCase()} · ${a.actionedAt.substring(0,10)}',
                        style: TextStyle(
                          fontSize: 12,
                          color: a.action == 'approved'
                              ? AppColors.success : AppColors.danger,
                        )),
                    if (a.comments != null && a.comments!.isNotEmpty)
                      Text('Note: ${a.comments}',
                          style: const TextStyle(fontSize: 12, color: Colors.black54)),
                  ],
                )),
              ]),
            )),
          ]),
        ],
      ]),
    );
  }
}

class _Section extends StatelessWidget {
  final String         title;
  final List<Widget>   children;
  const _Section({required this.title, required this.children});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title, style: const TextStyle(
          fontWeight: FontWeight.bold, fontSize: 15, color: AppColors.primary)),
      const SizedBox(height: 10),
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start,
            children: children),
      ),
    ],
  );
}

class _Row extends StatelessWidget {
  final String label, value;
  const _Row(this.label, this.value);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(children: [
      SizedBox(width: 120,
          child: Text(label, style: const TextStyle(color: Colors.black54))),
      Expanded(child: Text(value,
          style: const TextStyle(fontWeight: FontWeight.w500))),
    ]),
  );
}

class _SumCard extends StatelessWidget {
  final String label, value;
  final Color    color;
  final IconData icon;
  const _SumCard(this.label, this.value, this.color, this.icon);
  @override
  Widget build(BuildContext context) => Expanded(child: Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: color.withOpacity(0.08),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: color.withOpacity(0.3)),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, color: color, size: 20),
      const SizedBox(height: 6),
      Text(value, style: TextStyle(
          fontWeight: FontWeight.bold, fontSize: 16, color: color)),
      Text(label, style: const TextStyle(fontSize: 12, color: Colors.black54)),
    ]),
  ));
}

class _ContractSection extends StatelessWidget {
  final LoadsheetModel loadsheet;
  final VoidCallback? onUpload;

  const _ContractSection({required this.loadsheet, this.onUpload});

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;
    final isHR = user?.role == 'hr' || user?.role == 'admin';
    if (!isHR) return const SizedBox.shrink();

    final hasContract = loadsheet.contractUrl != null && loadsheet.contractUrl!.isNotEmpty;

    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.primary.withOpacity(0.04),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.primary.withOpacity(0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.description_outlined, size: 18, color: AppColors.primary),
              const SizedBox(width: 8),
              const Text(
                'Lecturer Contract',
                style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary),
              ),
              const Spacer(),
              if (hasContract)
                TextButton.icon(
                  onPressed: () => _viewContract(loadsheet.contractUrl!),
                  icon: const Icon(Icons.open_in_new, size: 16),
                  label: const Text('View PDF'),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    foregroundColor: AppColors.primary,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          if (!hasContract)
            const Text(
              'No contract uploaded for this lecturer.',
              style: TextStyle(fontSize: 12, color: Colors.black54, fontStyle: FontStyle.italic),
            ),
          if (isHR) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onUpload,
                icon: const Icon(Icons.upload_file, size: 18),
                label: Text(hasContract ? 'Update Contract' : 'Upload Contract'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  side: const BorderSide(color: AppColors.primary),
                  foregroundColor: AppColors.primary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _viewContract(String url) async {
    // Correct URL for local backend
    final fullUrl = ApiConstants.baseUrl.replaceAll('/api', '') + url;
    final uri = Uri.parse(fullUrl);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}