import 'package:timezone/timezone.dart' as tz;

/// 앱 전체에서 "오늘이 며칠인가"를 판단하는 유일한 기준(single source of
/// truth).
///
/// 여기서 이루어지는 모든 "오늘"/"같은 날" 판단(TTS 일일 turn 제한,
/// 세션을 이어서 할지 마무리할지, review 진행도의 만료 여부, 날짜별 history
/// 파일명 등)은 이제 기기의 로컬 달력이 아니라 **태평양 시간(Pacific
/// time) 기준 하루**로 정의된다 — Gemini 무료 등급의 일일 quota가 실제로
/// 리셋되는 시점이 바로 이 태평양 시간 자정이기 때문이다. 그렇지 않으면
/// 미국 밖의 학습자는 quota 자체가 리셋되는 시점보다 앱이 생각하는
/// "오늘"이 몇 시간 앞서거나 뒤처져 어긋날 수 있다. 고정된 UTC-8
/// 오프셋이 아니라 `America/Los_Angeles`를 쓰는 이유는 서머타임(DST)
/// 전환 구간에서도 이 계산이 계속 정확하도록 하기 위함이다.
///
/// 앱 시작 시(`main.dart` 참고) `package:timezone/data/latest.dart`의
/// `initializeTimeZones()`가 한 번 호출되어 있어야 하며, 그렇지 않으면
/// `tz.getLocation`이 예외를 던진다.
class DayBoundaryService {
  static final _pacific = tz.getLocation('America/Los_Angeles');

  /// [instant]가 속한 태평양 시간 기준 달력 날짜(시각 정보 없이 자정만
  /// 있는 `DateTime`)를 반환한다.
  ///
  /// [currentPacificDate]와 [isSamePacificDay]가 내부적으로 사용하며,
  /// `HistoryService`가 날짜별 history를 태평양 날짜로 저장할 때도
  /// 호출된다.
  /// [instant]: 변환할 임의의 시각.
  /// 반환값: 태평양 기준 달력 날짜(자정, `DateTime(year, month, day)`).
  DateTime pacificDateOf(DateTime instant) {
    final pacific = tz.TZDateTime.from(instant, _pacific);
    return DateTime(pacific.year, pacific.month, pacific.day);
  }

  /// 지금 이 순간의 태평양 기준 달력 날짜를 반환한다.
  /// `main.dart`의 시작 로그와 `app_router.dart`의 세션 재개 판단
  /// (해당 날짜의 `DayBoundaryService`) -> `SessionStateService`의 TTS
  /// 일일 사용량/리뷰 진행도 만료 판단 등에서 호출된다.
  /// 반환값: 태평양 기준 오늘 날짜.
  DateTime currentPacificDate() => pacificDateOf(DateTime.now());

  /// [a]와 [b]가 태평양 기준으로 같은 달력 날짜에 속하는지 판단한다.
  /// `app_router.dart`가 저장된 세션을 이어서 재개할지 판단할 때,
  /// `SessionStateService`가 TTS 일일 사용량과 review 진행도가 오늘 것인지
  /// 확인할 때 호출된다.
  /// 반환값: 같은 태평양 날짜이면 `true`.
  bool isSamePacificDay(DateTime a, DateTime b) => pacificDateOf(a) == pacificDateOf(b);
}
