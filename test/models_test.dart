import 'package:flutter_test/flutter_test.dart';

import 'package:mail/models.dart';

void main() {
  test('MailMessage keeps required server message identity', () {
    const MailMessage message = MailMessage(
      id: 'gmail-id',
      sender: 'sender@example.com',
      subject: 'Hello',
      date: null,
      body: 'Body',
    );

    expect(message.id, 'gmail-id');
    expect(message.sender, 'sender@example.com');
    expect(message.subject, 'Hello');
    expect(message.body, 'Body');
    expect(message.unread, isFalse);
  });
}
