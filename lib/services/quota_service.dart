// Export quota: 10 free minutes per day, rewarded ads add minutes.

import 'package:shared_preferences/shared_preferences.dart';

class QuotaService {
  static const _kDate = 'quota_date';
  static const _kFreeUsedSec = 'quota_free_used_sec';
  static const _kBonusSec = 'quota_bonus_sec';
  static const int freePerDaySec = 10 * 60;
  static const int secPerAd = 5 * 60;

  Future<void> _rollover(SharedPreferences p) async {
    final today = DateTime.now().toIso8601String().substring(0, 10);
    if (p.getString(_kDate) != today) {
      await p.setString(_kDate, today);
      await p.setInt(_kFreeUsedSec, 0);
    }
  }

  /// Total exportable seconds remaining right now.
  Future<int> remainingSec() async {
    final p = await SharedPreferences.getInstance();
    await _rollover(p);
    final freeLeft =
        freePerDaySec - (p.getInt(_kFreeUsedSec) ?? 0);
    final bonus = p.getInt(_kBonusSec) ?? 0;
    return (freeLeft + bonus).clamp(0, 1 << 31);
  }

  /// Try to consume [sec] for an export. Returns false if not enough.
  Future<bool> consume(int sec) async {
    final p = await SharedPreferences.getInstance();
    await _rollover(p);
    var freeUsed = p.getInt(_kFreeUsedSec) ?? 0;
    var bonus = p.getInt(_kBonusSec) ?? 0;
    var need = sec;
    final freeLeft = freePerDaySec - freeUsed;
    final takeFree = need.clamp(0, freeLeft);
    freeUsed += takeFree;
    need -= takeFree;
    if (need > bonus) return false;
    bonus -= need;
    await p.setInt(_kFreeUsedSec, freeUsed);
    await p.setInt(_kBonusSec, bonus);
    return true;
  }

  /// Refund seconds when an export fails.
  Future<void> refund(int sec) async {
    final p = await SharedPreferences.getInstance();
    await _rollover(p);
    // Refund to bonus first (simplest correct-enough accounting for v1).
    final bonus = (p.getInt(_kBonusSec) ?? 0) + sec;
    await p.setInt(_kBonusSec, bonus);
  }

  /// Grant bonus seconds after a rewarded ad.
  Future<void> grantAdReward() async {
    final p = await SharedPreferences.getInstance();
    await _rollover(p);
    await p.setInt(_kBonusSec, (p.getInt(_kBonusSec) ?? 0) + secPerAd);
  }
}
