// Run with: deno run --allow-read tests/strings.test.js
// Strings.js has no exports, so it is evaluated here rather than imported.

const source = Deno.readTextFileSync(new URL("../Strings.js", import.meta.url))
const Strings = new Function(
  source + "; return { localeKey, table, verdictPhrases }"
)()

let failures = 0

function check(name, actual, expected) {
  const ok = JSON.stringify(actual) === JSON.stringify(expected)
  if (!ok) {
    failures++
    console.log("FAIL " + name + "\n  expected " + JSON.stringify(expected) + "\n  got      " + JSON.stringify(actual))
  }
}

// Auto follows the system locale; a pinned language wins over the locale.
check("zh_CN auto is zh", Strings.localeKey("zh_CN"), "zh")
check("zh_TW auto is zh", Strings.localeKey("zh_TW"), "zh")
check("zh-Hans auto is zh", Strings.localeKey("zh-Hans"), "zh")
check("en_US auto is en", Strings.localeKey("en_US"), "en")
check("an unsupported locale falls back to en", Strings.localeKey("fr_FR"), "en")
check("a missing locale falls back to en", Strings.localeKey(""), "en")
check("the 中文 override pins zh", Strings.localeKey("en_US", "中文"), "zh")
check("the English override pins en", Strings.localeKey("zh_CN", "English"), "en")
check("Auto follows the locale", Strings.localeKey("zh_CN", "Auto"), "zh")
check("clear overrides follow the locale", Strings.localeKey("en_US", ""), "en")

const en = Strings.table("en")
const zh = Strings.table("zh")
const fr = Strings.table("fr")

check("an unsupported key keeps the English wording", fr.sectionLibrary, "LIBRARY")
check("the English headings", en.sectionLibrary, "LIBRARY")
check("the Chinese headings", zh.sectionLibrary, "音乐库")
check("the Chinese playlist heading", zh.sectionPlaylists, "歌单")
check("the English browse summary", en.browseLibrary, "Browse the library")
check("the Chinese browse summary", zh.browseLibrary, "浏览音乐库")
check("the Chinese search placeholder", zh.searchPlaceholder, "搜索歌单")
check("the English song filter placeholder", en.songSearchPlaceholder, "Filter by title or artist")
check("the Chinese transport tooltips", zh.togglePlayPause, "播放 / 暂停")
check("the English lyrics tooltip", en.hideLyrics, "Hide lyrics")
check("the Chinese footer version", zh.panelVersion, "版本")
check("the English footer GitHub", en.githubLink, "GitHub")
check("the Chinese nothing-matched", zh.nothingMatched, "没有匹配结果")
check("the Chinese start cliamp", zh.startCliamp, "启动 cliamp")
check("the English start cliamp", en.startCliamp, "Start cliamp")
check("the Chinese muted", zh.muted, "已静音")
check("the Chinese no output", zh.noOutput, "无输出设备")
check("the Chinese match rate", zh.matchRate, "匹配采样率")
check("the Chinese empty playlist", zh.playlistsEmpty, "没有找到歌单")
check("the Chinese pick a playlist", zh.pickPlaylist, "选择歌单")

// Count helpers keep the grammar of each language.
check("en results singular", en.results(1), "1 RESULT")
check("en results plural", en.results(4), "4 RESULTS")
check("zh results", zh.results(4), "4 个结果")
check("en tracks singular", en.tracksCount(1), "1 track")
check("en tracks plural", en.tracksCount(4), "4 tracks")
check("zh tracks", zh.tracksCount(4), "4 首")

// The two tables share every key, so a phrase can never silently drop to English.
const enKeys = Object.keys(en)
const zhKeys = Object.keys(zh)
check("both tables carry the same keys",
  enKeys.slice().sort().join(","), zhKeys.slice().sort().join(","))
check("every key that is a function exists in both", true,
  enKeys.every(function (k) { return typeof en[k] === typeof zh[k] }))

check("the English verdict phrases are null so Model keeps its wording", Strings.verdictPhrases("en"), null)
check("an English-only key keeps the reference verbs", Strings.verdictPhrases("fr"), null)
check("the Chinese verdict phrases exist", Strings.verdictPhrases("zh").bitPerfect, "位完美")
check("the rate slot is spelled the same way Model fills it",
  Strings.verdictPhrases("zh").outputHasNo.indexOf("{rate}") >= 0, true)
check("the Chinese verdict map covers every key",
  Object.keys(Strings.verdictPhrases("zh")).length, 11)

check("ten hero phrases in English", en.heroPhrases.length, 10)
check("ten hero phrases in Chinese", zh.heroPhrases.length, 10)
check("a Chinese phrase is really Chinese", zh.heroPhrases[0].length > 4, true)
check("the English phrases are the reference set", en.heroPhrases[0], "Bits arriving intact")

console.log(failures === 0 ? "all strings tests passed" : failures + " failing")
if (failures > 0) Deno.exit(1)