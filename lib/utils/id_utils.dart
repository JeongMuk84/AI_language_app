/// 새 대화 턴(conversation turn)에 부여할, 로컬에서 유일한(locally-unique)
/// id를 생성한다. 이 앱에서 호출부는 항상 순차적으로(항상 await되며)
/// 실행되므로 마이크로초 단위 timestamp만으로 충분하다 — 이를 위해
/// 별도의 UUID 패키지를 도입할 필요는 없다.
///
/// 반환값은 `DateTime.now().microsecondsSinceEpoch`를 문자열로 변환한
/// 값이다. `WritingViewModel`과 `ShadowingViewModel`이 새 턴을 시작할 때
/// `state.turnId`가 없으면 이 함수로 turn id를 발급한다.
String newTurnId() => DateTime.now().microsecondsSinceEpoch.toString();
