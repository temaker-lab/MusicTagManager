"""테스트 픽스처용 실제 API 응답 수집 (읽기 전용). MusicBrainz 1.1초, iTunes 3초 간격 준수.
AcoustID 응답은 키체인 키로 조회하고 키는 출력·저장하지 않는다."""
import json, os, subprocess, time, urllib.parse, urllib.request, unicodedata

OUT = os.path.join(os.path.dirname(__file__), "../Tests/MTMCoreTests/Fixtures")
UA = "MusicTagManager/0.1 ( temzzang@gmail.com )"

def get(url, name, delay):
    with urllib.request.urlopen(urllib.request.Request(url, headers={"User-Agent": UA}), timeout=20) as r:
        data = json.load(r)
    json.dump(data, open(os.path.join(OUT, name), "w"), ensure_ascii=False, indent=1)
    time.sleep(delay)
    return data

def mb(path, name, **q):
    return get("https://musicbrainz.org/ws/2/" + path + "?" + urllib.parse.urlencode({**q, "fmt": "json"}), name, 1.1)

artists = mb("artist", "mb_artist_search_iu.json", query='artist:"아이유" OR alias:"아이유"', limit=3)
iu = artists["artists"][0]["id"]
mb(f"artist/{iu}", "mb_artist_iu.json", inc="aliases")
releases = mb("release", "mb_release_search_flower2.json", query=f'release:"꽃갈피 둘" AND arid:{iu}', limit=10)
rel = next(r for r in releases["releases"] if r["title"] == "꽃갈피 둘")
mb(f"release/{rel['id']}", "mb_release_flower2.json", inc="recordings+artist-credits+release-groups+isrcs")
recs = mb("recording", "mb_recording_search_autumn_morning.json", query=f'recording:"가을 아침" AND arid:{iu}', limit=10)
mb(f"recording/{recs['recordings'][0]['id']}", "mb_recording_autumn_morning.json", inc="releases+release-groups+artist-credits+isrcs+media")

it = get("https://itunes.apple.com/search?" + urllib.parse.urlencode({"term": "아이유 꽃갈피 둘", "country": "US", "entity": "album", "limit": 5}),
         "itunes_album_search_flower2.json", 3)
cid = next(r["collectionId"] for r in it["results"] if "Flower Bookmark" in r["collectionName"])
get(f"https://itunes.apple.com/lookup?id={cid}&entity=song&country=US", "itunes_lookup_flower2.json", 3)

# AcoustID: '01 가을 아침.mp3' 지문 조회 결과
key = subprocess.run(["security", "find-generic-password", "-s", "MusicTagManager.AcoustID", "-a", "default", "-w"],
                     capture_output=True, text=True, check=True).stdout.strip()
root = os.path.expanduser("~/Music/Music/Media.localized/Music")
path = next(os.path.join(d, f) for d, _, fs in os.walk(root) for f in fs
            if unicodedata.normalize("NFC", f) == "01 가을 아침.mp3" and "꽃갈피 둘" in unicodedata.normalize("NFC", d))
fpcalc = os.path.join(os.path.dirname(__file__), "../Resources/bin/fpcalc")
fp = json.loads(subprocess.run([fpcalc, "-json", "-length", "120", path], capture_output=True, text=True).stdout)
body = urllib.parse.urlencode({"client": key, "duration": int(fp["duration"]), "fingerprint": fp["fingerprint"], "meta": "recordingids"}).encode()
with urllib.request.urlopen(urllib.request.Request("https://api.acoustid.org/v2/lookup", data=body), timeout=20) as r:
    json.dump(json.load(r), open(os.path.join(OUT, "acoustid_lookup_autumn_morning.json"), "w"), indent=1)
print("완료:", sorted(os.listdir(OUT)))
