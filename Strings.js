// Pure helpers for the Cliamp panel's interface language. No QML imports, so this
// file is testable with Deno. English is the reference set; the Chinese table mirrors
// its keys exactly, which the tests pin down.

var OVERRIDE_ZH = "中文"
var OVERRIDE_EN = "English"
var OVERRIDE_AUTO = "Auto"
var ZH_PREFIX = "zh"

// Sample input: Qt.locale().name ("zh_CN", "en_US", "fr_FR") and the manifest setting.
// Auto (or nothing) follows the system locale; zh-TW and zh-Hans both count as Chinese.
function localeKey(localeName, override) {
  var choice = String(override || "").trim()
  if (choice === OVERRIDE_ZH) return "zh"
  if (choice === OVERRIDE_EN) return "en"
  return String(localeName || "").toLowerCase().indexOf(ZH_PREFIX) === 0 ? "zh" : "en"
}

// The verdict's English phrasing lives in Model.js so it is neither maintained twice
// nor re-verified; English deliberately returns null, meaning "use the Model defaults".
function verdictPhrases(key) {
  if (key === "zh") return ZH_VERDICT_PHRASES
  return null
}

var ZH_VERDICT_PHRASES = {
  bitPerfect: "位完美",
  resampled: "已重采样",
  cliampResampled: "cliamp 已重采样",
  lossy: "有损",
  transcoded: "服务器已转码",
  eqApplied: "已应用 EQ",
  cliampVolumeApplied: "cliamp 音量已调整",
  outputVolumeApplied: "输出音量已调整",
  volumeApplied: "音量已调整",
  noResampling: "cliamp 后无重采样",
  outputHasNo: "输出无 {rate}"
}

var EN_PHRASES = [
  "Bits arriving intact",
  "Straight off your own shelf",
  "No middleman on this signal",
  "Clock locked to source",
  "Spinning up the platter",
  "Needle in the groove",
  "Nothing resampled here",
  "Self-hosted and loud",
  "Signal path is short",
  "Whipping the terminal"
]

var ZH_PHRASES = [
  "数据原封送达",
  "直接从自己的歌库播放",
  "这条信号没有中间商",
  "时钟锁定音源",
  "转盘转起来了",
  "唱针落进音轨",
  "全程不重采样",
  "自建服务器，音量拉满",
  "信号通路短又直",
  "终端甩起来了"
]

function enResults(n) {
  var v = Number(n)
  return v === 1 ? "1 RESULT" : v + " RESULTS"
}

function zhResults(n) {
  return Number(n) + " 个结果"
}

function enQueue(n) {
  var v = Number(n)
  return v === 1 ? "1 in queue" : v + " in queue"
}

function zhQueue(n) {
  return Number(n) + " 首在队列"
}

function enTracks(n) {
  var v = Number(n)
  return v === 1 ? "1 track" : v + " tracks"
}

function zhTracks(n) {
  return Number(n) + " 首"
}

function table(key) {
  var zh = key === "zh"
  return {
    sectionLibrary: zh ? "音乐库" : "LIBRARY",
    sectionPlaylists: zh ? "歌单" : "PLAYLISTS",
    sectionOutput: zh ? "输出" : "OUTPUT",
    sectionSignal: zh ? "信号" : "SIGNAL",
    sectionVolume: zh ? "音量" : "VOLUME",
    browseLibrary: zh ? "浏览音乐库" : "Browse the library",
    browseIcon: zh ? "浏览" : "Browse",
    searchPlaceholder: zh ? "搜索歌曲、专辑和歌单" : "Search songs, albums and playlists",
    nothingMatched: zh ? "没有匹配结果" : "Nothing matched",
    startCliamp: zh ? "启动 cliamp" : "Start cliamp",
    inQueue: zh ? zhQueue : enQueue,
    muted: zh ? "已静音" : "MUTED",
    matchRate: zh ? "匹配采样率" : "Match rate",
    noOutput: zh ? "无输出设备" : "No output",
    results: zh ? zhResults : enResults,
    tracksCount: zh ? zhTracks : enTracks,
    playlistsEmpty: zh ? "没有找到歌单" : "No playlists found",
    pickPlaylist: zh ? "选择歌单" : "Pick a playlist",
    heroPhrases: zh ? ZH_PHRASES : EN_PHRASES,
    verdict: verdictPhrases(key)
  }
}