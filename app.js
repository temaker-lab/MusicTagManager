// MusicTag Manager — landing page
// 최신 DMG 직접 다운로드 (버전과 무관한 고정 링크).
const DOWNLOAD_URL = "https://github.com/temaker-lab/MusicTagManager/releases/latest/download/MusicTagManager.dmg";

const i18n = {
  ko: {
    "nav.how": "사용법", "nav.features": "기능", "nav.privacy": "개인정보", "nav.install": "설치", "nav.download": "다운로드",
    "hero.title": "비어 있는 곡 정보, 알아서 채우다",
    "hero.sub": "Apple Music 보관함에서 앨범커버·제목·가수·앨범이 비어 있는 곡을 찾아 자동으로 식별하고, 당신이 확인한 곡만 안전하게 채웁니다.",
    "hero.download": "무료 다운로드",
    "badge.free": "완전 무료", "badge.noAccount": "계정 불필요", "badge.local": "100% 로컬 · 외부 전송 없음", "badge.undo": "언제든 되돌리기",
    "how.title": "네 단계로 끝",
    "how.sub": "보관함은 ‘적용’을 누를 때만 바뀌고, 모든 변경은 되돌릴 수 있습니다.",
    "how.scan.t": "스캔", "how.scan.d": "선택한 플레이리스트에서 앨범커버·제목·가수·앨범이 비어 있는 곡만 추려 보여 줍니다.",
    "how.identify.t": "식별", "how.identify.d": "MusicBrainz · iTunes · 오디오 지문으로 올바른 정보와 앨범커버를 신뢰도와 함께 제안합니다.",
    "how.review.t": "검토", "how.review.d": "신뢰도별로 확인하고, 직접 수정·미리 듣기로 다듬습니다. 결정 전엔 아무것도 기록되지 않습니다.",
    "how.apply.t": "적용", "how.apply.d": "확인한 곡만 Music 보관함에 기록하고 다시 읽어 확인합니다. 곡·앨범·작업 단위로 되돌릴 수 있습니다.",
    "feat.title": "꼼꼼하고 안전하게",
    "feat.scan.t": "빈 항목만 콕 집어", "feat.scan.d": "이미 완비된 곡은 건드리지 않아, 손봐야 할 곡에만 집중합니다.",
    "feat.sources.t": "여러 소스로 식별", "feat.sources.d": "MusicBrainz·iTunes·오디오 지문(AcoustID)을 함께 써서 더 정확하게 찾습니다.",
    "feat.confidence.t": "신뢰도 표시", "feat.confidence.d": "높음·보통·낮음으로 표시돼 확실한 결과를 한눈에 믿고 쓸 수 있습니다.",
    "feat.artwork.t": "앨범커버 자동·검색", "feat.artwork.d": "고해상도 커버를 자동으로 찾고, 직접 검색하거나 이미지를 붙여 넣을 수도 있습니다.",
    "feat.edit.t": "직접 수정 · 미리 듣기", "feat.edit.d": "값을 손으로 고치고, 그 자리에서 곡을 재생해 확인할 수 있습니다.",
    "feat.undo.t": "되돌리기 · 스냅샷", "feat.undo.d": "적용 전 상태를 스냅샷으로 남겨, 곡·앨범·작업 단위로 언제든 되돌립니다.",
    "feat.lang.t": "한국어 · English", "feat.lang.d": "설정에서 언어를 바꾸면 즉시 전환됩니다.",
    "feat.history.t": "작업 이력 · 내보내기", "feat.history.d": "모든 적용 기록을 남기고, CSV로 내보내거나 가져올 수 있습니다.",
    "priv.title": "당신의 음악은 당신의 기기에",
    "priv.sub": "계정도, 서버도 없습니다. 모든 데이터는 이 Mac에만 저장됩니다.",
    "priv.1": "곡 정보와 설정은 <code>~/Library/Application&nbsp;Support</code> 아래에만 저장됩니다.",
    "priv.2": "외부로 보내는 것은 식별을 위한 제목·가수 등 검색어뿐이며, 그 외 개인정보는 수집하지 않습니다.",
    "priv.3": "MusicBrainz·iTunes·AcoustID·Cover Art Archive·Deezer는 곡 정보와 커버를 조회하는 데만 쓰입니다.",
    "priv.4": "보관함은 당신이 ‘적용’을 누를 때만 바뀌고, 언제든 되돌릴 수 있습니다.",
    "install.title": "설치 방법",
    "install.1": "아래 버튼으로 DMG를 내려받아 <b>MusicTag&nbsp;Manager</b>를 <b>응용 프로그램</b>으로 끌어다 놓습니다.",
    "install.2": "처음 실행하면 온보딩이 안내합니다. Music 앱 제어와 보관함 읽기 권한을 허용해 주세요(이유를 먼저 설명합니다).",
    "install.3": "정리할 플레이리스트를 고르면 준비 끝 — 스캔·식별·검토·적용으로 바로 이어집니다.",
    "install.req": "macOS 14(Sonoma) 이상 · Apple&nbsp;Silicon·Intel",
    "faq.q1": "내 음악 파일이 외부로 전송되나요?",
    "faq.a1": "아니요. 오디오 파일은 기기를 벗어나지 않습니다. 식별을 위해 제목·가수 같은 텍스트 검색어와 오디오 지문(해시)만 조회에 사용됩니다.",
    "faq.q2": "실수로 바꾼 걸 되돌릴 수 있나요?",
    "faq.a2": "네. 적용 전 상태를 스냅샷으로 남겨, 곡·앨범·작업 단위로 언제든 되돌릴 수 있습니다.",
    "faq.q3": "왜 권한이 필요한가요?",
    "faq.a3": "보관함의 곡 정보를 ‘읽기’ 위해 미디어 접근, 변경을 ‘쓰기’ 위해 Music 앱 제어 권한이 필요합니다. 두 권한 모두 Mac 안에서만 쓰입니다.",
    "faq.q4": "유료인가요?",
    "faq.a4": "무료입니다. 계정 생성이나 개인정보 제공도 필요 없습니다.",
    "faq.q5": "어떤 macOS가 필요한가요?",
    "faq.a5": "macOS 14 (Sonoma) 이상에서 동작합니다. Apple Silicon과 Intel 모두 지원합니다.",
    "footer.tag": "비어 있는 곡 정보를 알아서 채우는 macOS 앱.",
    "footer.contact": "문의·피드백",
    "footer.credits": "곡 정보 제공: MusicBrainz · iTunes · AcoustID · Cover Art Archive · Deezer",
  },
  en: {
    "nav.how": "How", "nav.features": "Features", "nav.privacy": "Privacy", "nav.install": "Install", "nav.download": "Download",
    "hero.title": "Fill in your music’s missing tags, automatically",
    "hero.sub": "Finds tracks in your Apple Music library that are missing artwork, title, artist, or album, identifies them, and fills in only the ones you confirm — safely.",
    "hero.download": "Download free",
    "badge.free": "Completely free", "badge.noAccount": "No account", "badge.local": "100% local · nothing uploaded", "badge.undo": "Undo anytime",
    "how.title": "Four simple steps",
    "how.sub": "Your library changes only when you press Apply — and everything is undoable.",
    "how.scan.t": "Scan", "how.scan.d": "Lists only the tracks in your chosen playlists that are missing artwork, title, artist, or album.",
    "how.identify.t": "Identify", "how.identify.d": "Proposes the right info and artwork via MusicBrainz · iTunes · audio fingerprint, each with a confidence level.",
    "how.review.t": "Review", "how.review.d": "Check by confidence and refine with Edit and preview playback. Nothing is written until you decide.",
    "how.apply.t": "Apply", "how.apply.d": "Writes only the tracks you confirm and verifies them. Undo by track, album, or whole run.",
    "feat.title": "Thorough and safe",
    "feat.scan.t": "Only what needs work", "feat.scan.d": "Already-complete tracks are left alone, so you focus only on what matters.",
    "feat.sources.t": "Multi-source matching", "feat.sources.d": "Combines MusicBrainz, iTunes, and audio fingerprint (AcoustID) for accuracy.",
    "feat.confidence.t": "Confidence levels", "feat.confidence.d": "High / Medium / Low so you can trust strong matches at a glance.",
    "feat.artwork.t": "Artwork, found for you", "feat.artwork.d": "Fetches high-res covers automatically, or search and paste your own image.",
    "feat.edit.t": "Edit · preview", "feat.edit.d": "Fix values by hand and play the track right there to confirm.",
    "feat.undo.t": "Undo · snapshots", "feat.undo.d": "Every change keeps a snapshot — undo by track, album, or whole run anytime.",
    "feat.lang.t": "English · 한국어", "feat.lang.d": "Switch language in Settings and it changes instantly.",
    "feat.history.t": "History · export", "feat.history.d": "Keeps a record of every apply, and exports/imports via CSV.",
    "priv.title": "Your music stays on your Mac",
    "priv.sub": "No account, no server. All data lives on this Mac only.",
    "priv.1": "Track info and settings are stored only under <code>~/Library/Application&nbsp;Support</code>.",
    "priv.2": "The only thing sent out is search text (title, artist) for identification — no other personal data is collected.",
    "priv.3": "MusicBrainz, iTunes, AcoustID, Cover Art Archive, and Deezer are used only to look up track info and covers.",
    "priv.4": "Your library changes only when you press Apply, and every change can be undone.",
    "install.title": "How to install",
    "install.1": "Download the DMG below and drag <b>MusicTag&nbsp;Manager</b> into <b>Applications</b>.",
    "install.2": "On first launch, onboarding guides you. Allow Control Music app and Read Music library (the reasons are explained first).",
    "install.3": "Pick the playlists to clean up and you’re set — scan, identify, review, and apply right away.",
    "install.req": "macOS 14 (Sonoma) or later · Apple&nbsp;Silicon·Intel",
    "faq.q1": "Are my music files uploaded anywhere?",
    "faq.a1": "No. Audio files never leave your device. Only text search terms (title, artist) and an audio fingerprint (a hash) are used for lookups.",
    "faq.q2": "Can I undo a change I made by mistake?",
    "faq.a2": "Yes. A snapshot is kept before applying, so you can undo by track, album, or whole run anytime.",
    "faq.q3": "Why are permissions needed?",
    "faq.a3": "Media access to ‘read’ track info, and Control Music app to ‘write’ changes. Both are used only on your Mac.",
    "faq.q4": "Is it paid?",
    "faq.a4": "It’s free. No account or personal information required.",
    "faq.q5": "Which macOS is required?",
    "faq.a5": "macOS 14 (Sonoma) or later. Both Apple Silicon and Intel are supported.",
    "footer.tag": "A macOS app that fills in your music’s missing tags.",
    "footer.contact": "Contact · feedback",
    "footer.credits": "Track data by MusicBrainz · iTunes · AcoustID · Cover Art Archive · Deezer",
  },
};

function applyLang(lang) {
  const dict = i18n[lang] || i18n.ko;
  document.documentElement.setAttribute("lang", lang);
  document.documentElement.setAttribute("data-lang", lang);
  document.querySelectorAll("[data-i18n]").forEach((el) => {
    const key = el.getAttribute("data-i18n");
    if (dict[key] != null) el.innerHTML = dict[key];
  });
  const toggle = document.getElementById("langToggle");
  if (toggle) toggle.textContent = lang === "ko" ? "EN" : "한국어";
  try { localStorage.setItem("mtm.lang", lang); } catch (_) {}
}

function initLang() {
  let lang;
  // ?lang=ko|en 로 명시하면 그 값을 우선 (공유 링크·미리보기용)
  const q = new URLSearchParams(location.search).get("lang");
  if (q === "ko" || q === "en") lang = q;
  if (!lang) { try { lang = localStorage.getItem("mtm.lang"); } catch (_) {} }
  if (!lang) lang = (navigator.language || "en").toLowerCase().startsWith("ko") ? "ko" : "en";
  applyLang(lang);
}

document.addEventListener("DOMContentLoaded", () => {
  initLang();
  const toggle = document.getElementById("langToggle");
  if (toggle) {
    toggle.addEventListener("click", () => {
      const next = document.documentElement.getAttribute("data-lang") === "ko" ? "en" : "ko";
      applyLang(next);
    });
  }
  // 다운로드 링크 연결 (배포 시 DOWNLOAD_URL 교체)
  document.querySelectorAll(".js-download").forEach((a) => { a.href = DOWNLOAD_URL; });
  const year = document.getElementById("year");
  if (year) year.textContent = String(new Date().getFullYear());
});
