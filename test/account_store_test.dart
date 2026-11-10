import 'package:emby_downloader/emby/models.dart';
import 'package:emby_downloader/storage/session_store.dart';
import 'package:flutter_test/flutter_test.dart';

EmbySession _session({required String userId, required String name, String base = 'http://192.168.1.8:8096'}) {
  return EmbySession(
    base: base,
    apiPrefix: '/emby',
    serverName: '客厅',
    serverId: 'server',
    serverVersion: '4.8.11.0',
    userId: userId,
    username: name,
    accessToken: 'token-$userId',
    allowBadCertificate: userId == 'b',
  );
}

void main() {
  test('a single saved session becomes the active account', () async {
    final box = MemorySecureBox();
    await box.write('session', '{"base":"http://192.168.1.8:8096","apiPrefix":"/emby","serverName":"客厅","serverId":"s","serverVersion":"4.8","userId":"old","username":"周","accessToken":"tok","allowBadCertificate":true}');
    final store = SessionStore(box: box);
    final book = await store.loadBook();
    expect(book.accounts, hasLength(1));
    expect(book.active?.session.username, '周');
    expect(book.active?.session.allowBadCertificate, isTrue);
    expect(await box.read('session'), isNull);
    expect((await store.read())?.userId, 'old');
  });

  test('two accounts stay separate when one token is marked expired', () async {
    final store = SessionStore(box: MemorySecureBox());
    await store.upsert(_session(userId: 'a', name: '甲'));
    await store.upsert(_session(userId: 'b', name: '乙', base: 'http://10.0.0.2:8096'));
    var book = await store.loadBook();
    expect(book.accounts, hasLength(2));
    expect(book.active?.session.username, '乙');

    await store.markReauth(_session(userId: 'b', name: '乙', base: 'http://10.0.0.2:8096'));
    book = await store.loadBook();
    expect(book.accounts.singleWhere((account) => account.session.userId == 'a').needsReauth, isFalse);
    expect(book.accounts.singleWhere((account) => account.session.userId == 'b').needsReauth, isTrue);
    expect(book.accounts.singleWhere((account) => account.session.userId == 'b').session.accessToken, 'token-b');

    book = await store.remove(accountId(_session(userId: 'b', name: '乙', base: 'http://10.0.0.2:8096')));
    expect(book.accounts, hasLength(1));
    expect(book.active?.session.username, '甲');
  });
}
