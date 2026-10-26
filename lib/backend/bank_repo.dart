import 'backend.dart';

class BankAccountInfo {
  const BankAccountInfo({
    required this.bankName,
    required this.branch,
    required this.accountName,
    required this.accountNumber,
    required this.ifsc,
    required this.isSample,
  });
  final String bankName;
  final String branch;
  final String accountName;
  final String accountNumber;
  final String ifsc;
  final bool isSample;
}

class BankChangePending {
  const BankChangePending({
    required this.status,
    required this.bankName,
    required this.maskedNumber,
    required this.approvalRef,
    this.effectiveAt,
  });
  final String status;
  final String bankName;
  final String maskedNumber;
  final String? approvalRef;
  final DateTime? effectiveAt;
}

class BankOverview {
  const BankOverview({this.account, this.pending, required this.canChange});
  final BankAccountInfo? account;
  final BankChangePending? pending;
  final bool canChange;
}

class EcVoteEntry {
  const EcVoteEntry({required this.name, required this.vote, this.comment});
  final String name;
  final String vote;
  final String? comment;
}

class EcVoteSummary {
  const EcVoteSummary({
    required this.total,
    required this.yes,
    required this.no,
    required this.needed,
    required this.open,
    required this.canVote,
    required this.votes,
    this.myVote,
  });
  final int total;
  final int yes;
  final int no;
  final int needed;
  final bool open;
  final bool canVote;
  final String? myVote;
  final List<EcVoteEntry> votes;
}

class BankRepo {
  static Future<BankOverview> overview() async {
    final data = Map<String, dynamic>.from(await db.rpc('current_bank_account') as Map);
    final acc = data['account'] as Map?;
    final pen = data['pending'] as Map?;
    return BankOverview(
      canChange: data['can_change'] as bool? ?? false,
      account: acc == null
          ? null
          : BankAccountInfo(
              bankName: acc['bank_name'] as String,
              branch: acc['branch'] as String? ?? '',
              accountName: acc['account_name'] as String,
              accountNumber: acc['account_number'] as String,
              ifsc: acc['ifsc'] as String,
              isSample: acc['is_sample'] as bool? ?? false,
            ),
      pending: pen == null
          ? null
          : BankChangePending(
              status: pen['status'] as String,
              bankName: pen['bank_name'] as String,
              maskedNumber: pen['masked_number'] as String,
              approvalRef: pen['approval_ref'] as String?,
              effectiveAt: pen['effective_at'] == null ? null : DateTime.parse(pen['effective_at'] as String).toLocal(),
            ),
    );
  }

  static Future<void> requestChange({
    required String bankName,
    required String branch,
    required String accountName,
    required String accountNumber,
    required String ifsc,
    required String reason,
    required String momRef,
  }) => db.rpc(
    'request_bank_account_change',
    params: {
      'p_bank_name': bankName,
      'p_branch': branch,
      'p_account_name': accountName,
      'p_account_number': accountNumber,
      'p_ifsc': ifsc,
      'p_reason': reason,
      'p_mom_ref': momRef,
    },
  );

  static Future<EcVoteSummary> ecSummary(String requestId) async {
    final d = Map<String, dynamic>.from(await db.rpc('ec_vote_summary', params: {'p_request': requestId}) as Map);
    return EcVoteSummary(
      total: (d['total'] as num).toInt(),
      yes: (d['yes'] as num).toInt(),
      no: (d['no'] as num).toInt(),
      needed: (d['needed'] as num).toInt(),
      open: d['open'] as bool? ?? false,
      canVote: d['can_vote'] as bool? ?? false,
      myVote: d['my_vote'] as String?,
      votes: [
        for (final v in d['votes'] as List)
          EcVoteEntry(name: v['name'] as String, vote: v['vote'] as String, comment: v['comment'] as String?),
      ],
    );
  }

  static Future<void> castVote(String requestId, String vote, String? comment) =>
      db.rpc('cast_ec_vote', params: {'p_request': requestId, 'p_vote': vote, 'p_comment': comment});
}
