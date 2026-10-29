import Foundation

/// 앱이 지역화 문자열을 공급하는 훅.
/// 앱은 시작 시 `MTMLoc.translate = { key in appLookup(key) }` 로 연결한다.
/// 연결하지 않은 경우(또는 키가 없는 경우)에는 호출부가 넘긴 한국어 기본값을 그대로 쓴다
/// → CLI 도구(MTMIdentify 등)나 테스트에서는 기존처럼 한국어로 보인다.
public enum MTMLoc {
    /// 키 → 지역화 문자열. 기본은 키를 그대로 돌려준다(= 기본값 사용).
    nonisolated(unsafe) public static var translate: (String) -> String = { $0 }

    /// 지역화 문자열. 앱이 키를 모르면(또는 미연결) `fallback`(한국어)을 쓴다.
    public static func t(_ key: String, _ fallback: String) -> String {
        let value = translate(key)
        return value == key ? fallback : value
    }

    /// 포맷 인자가 있는 지역화 문자열. 템플릿(앱 문자열 또는 fallback)에 인자를 채운다.
    public static func f(_ key: String, _ fallback: String, _ args: CVarArg...) -> String {
        String(format: t(key, fallback), arguments: args)
    }
}
