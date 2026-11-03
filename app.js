// MusicTag Manager — landing page
// 최신 DMG 직접 다운로드 (버전과 무관한 고정 링크).
const DOWNLOAD_URL = "https://github.com/temaker-lab/MusicTagManager/releases/latest/download/MusicTagManager.dmg";

const i18n = {
  ko: {
    "nav.how": "사용법", "nav.screens": "화면", "nav.features": "기능", "nav.privacy": "개인정보", "nav.install": "설치", "nav.download": "다운로드",
    "hero.title": "비어 있는 곡 정보, 알아서 채워드려요",
    "hero.sub": "Apple Music 보관함에서 앨범커버·제목·가수·앨범이 비어 있는 곡을 찾아 자동으로 식별하고, 확인한 곡만 안전하게 채워드려요.",
    "hero.download": "무료 다운로드",
    "badge.free": "완전 무료", "badge.noAccount": "계정 불필요", "badge.local": "100% 로컬 · 외부 전송 없음", "badge.undo": "언제든 되돌리기",
    "how.title": "정리는 네 단계면 끝나요",
    "how.sub": "마음에 안 드는 부분이 있어도 괜찮아요. 보관함은 ‘적용’을 누를 때만 바뀌고, 어떤 변경이든 언제든 되돌릴 수 있으니까요.",
    "how.scan.t": "플레이리스트 고르기", "how.scan.d": "정리할 플레이리스트를 선택하면, 그 안에서 앨범 커버·제목·가수·앨범 정보가 비어 있는 곡만 골라 보여드려요.",
    "how.identify.t": "오디오 지문으로 찾기", "how.identify.d": "제목이나 가수가 없어도 괜찮아요. 오디오 지문(AcoustID)과 MusicBrainz·iTunes를 함께 조회해 올바른 정보를 신뢰도와 함께 찾아드려요.",
    "how.review.t": "필요하면 직접 수정", "how.review.d": "식별 결과가 애매하면 값을 직접 고치고, 커버를 검색하거나 붙여넣고, 그 자리에서 바로 재생해 확인할 수 있어요.",
    "how.apply.t": "앨범아트까지 한 번에", "how.apply.d": "확인한 곡만 Music 보관함에 기록해요. 앨범아트까지 함께 저장되고, 곡·앨범·작업 단위로 언제든 되돌릴 수 있어요.",
    "how.note": "확인하지 않은 곡은 그대로 남아 있어요. ‘적용’을 누르기 전까지는 보관함에 아무 일도 일어나지 않습니다.",
    "screens.title": "실제 화면 둘러보기",
    "screens.sub": "스캔부터 식별·검토·이력까지, 앱에서 보게 될 화면 그대로예요.",
    "screens.scan.t": "한눈에 보이는 정리 대상",
    "screens.scan.d": "선택한 플레이리스트에서 앨범커버·제목·가수·앨범이 비어 있는 곡만 추려, 무엇이 비었는지 그래프와 목록으로 보여드려요.",
    "screens.results.t": "식별 결과를 신뢰도와 함께",
    "screens.results.d": "여러 소스가 제안한 새 값과 바뀔 내용을 신뢰도(높음·보통·낮음)별로 정리해, 믿을 수 있는 결과를 한눈에 확인할 수 있어요.",
    "screens.edit.t": "직접 수정 · 앨범커버 · 미리 듣기",
    "screens.edit.d": "값을 손으로 다듬고, 커버를 검색하거나 붙여 넣고, 그 자리에서 곡을 재생해 확인할 수 있어요. 적용 전 상태는 스냅샷으로 남아 되돌릴 수 있어요.",
    "screens.history.t": "모든 변경은 작업 이력에",
    "screens.history.d": "적용한 내용이 시간순으로 기록되고, 곡·앨범·작업 단위로 언제든 되돌릴 수 있어요.",
    "feat.title": "꼼꼼하고 안전하게",
    "feat.scan.t": "빈 항목만 콕 집어", "feat.scan.d": "이미 완비된 곡은 건드리지 않아, 손봐야 할 곡에만 집중해요.",
    "feat.sources.t": "여러 소스로 식별", "feat.sources.d": "MusicBrainz·iTunes·오디오 지문(AcoustID)을 함께 써서 더 정확하게 찾아드려요.",
    "feat.confidence.t": "신뢰도 표시", "feat.confidence.d": "높음·보통·낮음으로 표시돼 확실한 결과를 한눈에 믿고 쓸 수 있어요.",
    "feat.artwork.t": "앨범커버 자동·검색", "feat.artwork.d": "고해상도 커버를 자동으로 찾고, 직접 검색하거나 이미지를 붙여 넣을 수도 있어요.",
    "feat.edit.t": "직접 수정 · 미리 듣기", "feat.edit.d": "값을 손으로 고치고, 그 자리에서 곡을 재생해 확인할 수 있어요.",
    "feat.undo.t": "되돌리기 · 스냅샷", "feat.undo.d": "적용 전 상태를 스냅샷으로 남겨, 곡·앨범·작업 단위로 언제든 되돌릴 수 있어요.",
    "feat.lang.t": "한국어 · English", "feat.lang.d": "설정에서 언어를 바꾸면 즉시 바뀌어요.",
    "feat.history.t": "작업 이력 · 내보내기", "feat.history.d": "모든 적용 기록을 남기고, CSV로 내보내거나 가져올 수 있어요.",
    "priv.title": "내 음악은 내 기기에",
    "priv.sub": "계정도, 서버도 없어요. 모든 데이터는 이 Mac에만 저장돼요.",
    "priv.1": "곡 정보와 설정은 <code>~/Library/Application&nbsp;Support</code> 아래에만 저장돼요.",
    "priv.2": "외부로 보내는 것은 식별을 위한 제목·가수 등 검색어뿐이고, 그 외 개인정보는 수집하지 않아요.",
    "priv.3": "MusicBrainz·iTunes·AcoustID·Cover Art Archive·Deezer는 곡 정보와 커버를 조회하는 데만 쓰여요.",
    "priv.4": "보관함은 ‘적용’을 누를 때만 바뀌고, 언제든 되돌릴 수 있어요.",
    "install.title": "설치 방법",
    "install.fig1": "응용 프로그램 폴더로 드래그",
    "install.fig2": "우클릭 → 열기",
    "install.fig3": "개인정보 보호 및 보안 → 확인 없이 열기",
    "install.1": "아래 버튼으로 <b>DMG</b>를 내려받아 두 번 클릭하면 설치 창이 열려요. <b>MusicTag&nbsp;Manager</b> 아이콘을 <b>응용 프로그램</b> 폴더로 끌어다 놓으세요.",
    "install.2": "응용 프로그램에서 앱을 <b>우클릭(Control‑클릭) → 열기</b>로 처음 한 번 실행하세요.",
    "install.3": "“열 수 없습니다”라고 차단되면 <b>시스템 설정 → 개인정보 보호 및 보안</b>으로 가서, 맨 아래 <b>“‘MusicTag&nbsp;Manager’은(는) 확인되지 않은 개발자…”</b> 옆의 <b>“확인 없이 열기”</b>를 누르고 다시 <b>열기</b>를 선택하세요.",
    "install.4": "처음 실행하면 온보딩이 안내해요. Music 앱 제어와 보관함 읽기 권한을 허용해 주세요(이유를 먼저 설명해드려요).",
    "install.5": "정리할 플레이리스트를 고르면 준비 끝 — 스캔·식별·검토·적용으로 바로 이어져요.",
    "install.note": "‘확인되지 않은 개발자’ 안내는 Apple 공증을 거치지 않은 무료 앱이라 나타나고, 위 과정은 <b>최초 1회</b>만 하면 돼요. 이후 실행과 자동 업데이트는 경고 없이 진행돼요.",
    "install.req": "macOS 14(Sonoma) 이상 · Apple&nbsp;Silicon·Intel",
    "faq.q1": "내 음악 파일이 외부로 전송되나요?",
    "faq.a1": "아니요. 오디오 파일은 기기를 벗어나지 않아요. 식별을 위해 제목·가수 같은 텍스트 검색어와 오디오 지문(해시)만 조회에 사용해요.",
    "faq.q2": "실수로 바꾼 걸 되돌릴 수 있나요?",
    "faq.a2": "네. 적용 전 상태를 스냅샷으로 남겨서, 곡·앨범·작업 단위로 언제든 되돌릴 수 있어요.",
    "faq.q3": "왜 권한이 필요한가요?",
    "faq.a3": "보관함의 곡 정보를 ‘읽기’ 위해 미디어 접근 권한이, 변경을 ‘쓰기’ 위해 Music 앱 제어 권한이 필요해요. 두 권한 모두 Mac 안에서만 쓰여요.",
    "faq.q4": "유료인가요?",
    "faq.a4": "무료예요. 계정 생성이나 개인정보 제공도 필요 없어요.",
    "faq.q5": "어떤 macOS가 필요한가요?",
    "faq.a5": "macOS 14(Sonoma) 이상에서 동작해요. Apple Silicon과 Intel 모두 지원해요.",
    "footer.tag": "비어 있는 곡 정보를 알아서 채워 주는 macOS 앱이에요.",
    "footer.contact": "문의·피드백",
    "footer.credits": "곡 정보 제공: MusicBrainz · iTunes · AcoustID · Cover Art Archive · Deezer",
  },
  en: {
    "nav.how": "How", "nav.screens": "Screens", "nav.features": "Features", "nav.privacy": "Privacy", "nav.install": "Install", "nav.download": "Download",
    "hero.title": "Fill in your music’s missing tags, automatically",
    "hero.sub": "Finds tracks in your Apple Music library that are missing artwork, title, artist, or album, identifies them, and fills in only the ones you confirm — safely.",
    "hero.download": "Download free",
    "badge.free": "Completely free", "badge.noAccount": "No account", "badge.local": "100% local · nothing uploaded", "badge.undo": "Undo anytime",
    "how.title": "Four simple steps",
    "how.sub": "Your library changes only when you press Apply — and everything is undoable.",
    "how.scan.t": "Pick your playlists", "how.scan.d": "Choose the playlists to clean up, and it gathers only the songs missing artwork, title, artist, or album.",
    "how.identify.t": "Identify by audio fingerprint", "how.identify.d": "Even with no title or artist, audio fingerprint (AcoustID) plus MusicBrainz and iTunes find the right info with a confidence rating.",
    "how.review.t": "Edit by hand too", "how.review.d": "When a match is unclear, fix values yourself, search or paste cover art, and play the track right there to check.",
    "how.apply.t": "Apply — artwork and all", "how.apply.d": "Writes only the songs you confirm to your Music library — album art included. Undo by track, album, or whole run.",
    "how.note": "Tracks you don’t confirm stay exactly as they are. Nothing happens to your library until you press Apply.",
    "screens.title": "A look inside",
    "screens.sub": "From scan to identify, review, and history — exactly what you’ll see in the app.",
    "screens.scan.t": "See what needs cleaning at a glance",
    "screens.scan.d": "From the playlists you choose, it gathers only the songs missing artwork, title, artist, or album — and shows what’s missing as a chart and a list.",
    "screens.results.t": "Results with a confidence rating",
    "screens.results.d": "New values proposed by multiple sources and the exact changes are grouped by confidence (High · Medium · Low), so trustworthy results stand out instantly.",
    "screens.edit.t": "Edit, artwork & preview",
    "screens.edit.d": "Fine‑tune values by hand, search or paste cover art, and play the song right there to check. The pre‑apply state is kept as a snapshot you can undo.",
    "screens.history.t": "Every change, in History",
    "screens.history.d": "Everything you apply is logged in order, and you can undo it per song, per album, or per job anytime.",
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
    "install.fig1": "Drag to the Applications folder",
    "install.fig2": "Right‑click → Open",
    "install.fig3": "Privacy & Security → Open Anyway",
    "install.1": "Download the <b>DMG</b> below and double‑click it to open the installer window. Drag the <b>MusicTag&nbsp;Manager</b> icon onto the <b>Applications</b> folder.",
    "install.2": "In Applications, <b>right‑click (Control‑click) the app → Open</b> once for the first launch.",
    "install.3": "If it’s blocked with “can’t be opened,” go to <b>System Settings → Privacy &amp; Security</b>, scroll down to <b>“‘MusicTag&nbsp;Manager’ was blocked…”</b> and click <b>“Open Anyway,”</b> then choose <b>Open</b> again.",
    "install.4": "On first launch, onboarding guides you. Allow Control Music app and Read Music library (the reasons are explained first).",
    "install.5": "Pick the playlists to clean up and you’re set — scan, identify, review, and apply right away.",
    "install.note": "The “unidentified developer” prompt appears because this is a free app not notarized by Apple. The steps above are needed <b>only once</b>; later launches and auto‑updates run without warnings.",
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
