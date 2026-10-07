class MailMessage {
  const MailMessage({required this.id, required this.sender, required this.subject, required this.date, required this.body, this.unread = false});
  final String id;
  final String sender;
  final String subject;
  final DateTime? date;
  final String body;
  final bool unread;
}

class MailAccount {
  const MailAccount({required this.email, this.displayName, this.photoUrl});
  final String email;
  final String? displayName;
  final String? photoUrl;
}
