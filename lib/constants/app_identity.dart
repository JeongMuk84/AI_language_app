/// 앱의 디스크 저장 폴더 이름에 대한 단일 진실 원천(single source of
/// truth) 상수 — `StorageLocationService`가 base directory 경로를 만들
/// 때 사용한다. 이 문자열을 다른 곳에 다시 하드코딩하지 말 것.
///
/// 의도적으로 `package_info_plus`에서 값을 가져오지 않는다: 그렇게 하면
/// 어차피 릴리스 기간 내내 고정인 값 하나를 위해, 경로 문자열을
/// 만들기도 전에 매번 비동기 platform-channel 호출에 의존하게 되기
/// 때문이다. 플랫폼별 앱 이름(main.dart의 `MaterialApp` title,
/// windows/runner/main.cpp의 Windows 창 제목, Android의 android:label)과는
/// 오직 컨벤션(BY CONVENTION)으로만 값을 맞춰둔 것이며, 그쪽 어디에서도
/// 이 상수를 다시 읽어가지 않는다 — 각각이 자기 플랫폼의 독립된 정적
/// 메타데이터이기 때문이다. 따라서 앱 이름을 다시 바꾸게 되면 그
/// 플랫폼별 값들과 이 상수를 모두 함께 갱신해야 한다.
const String kAppFolderName = 'La Fly';
