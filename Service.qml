import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire
import "Model.js" as Model

Item {
  id: root

  property var settings: ({})
  // The panel writes this so nothing polls while the popup is shut.
  property bool panelOpen: false
  // Injected by Panel, which computes the interface language; verdict() reads the
  // phrase table out of it. An empty object keeps every English sentence intact.
  property var strings: ({})

  // Rate following has to notice a track change with nothing on screen, so it is the
  // second consumer of cliamp's status and keeps the poll alive on its own.
  readonly property bool wantsStatus: panelOpen || followNativeRate

  property var status: Model.defaultStatus()
  property string lastError: ""

  readonly property string cliampPath: String(setting("cliampPath", "") || "cliamp")
  readonly property int statusIntervalMs: intSetting("statusIntervalSec", 2, 1, 10) * 1000

  // Bound by cliamp's own bus name, never to whichever player happens to be active,
  // because Chromium and others register MPRIS too and would otherwise drive this panel.
  // Re-resolved on every player list change. A function call binding does not reliably
  // re-evaluate when the daemon restarts, which strands the panel on a dead object.
  property var player: null

  function refreshPlayer() { player = findCliampPlayer() }

  Connections {
    target: Mpris.players
    ignoreUnknownSignals: true
    function onValuesChanged() { root.refreshPlayer() }
  }

  Component.onCompleted: {
    refreshPlayer()
    rebuildNodes()
  }

  // cliamp's own status is the truth. MPRIS only fills gaps and provides seeking, so a
  // stale or missing player object can no longer freeze the panel.
  readonly property bool running: status.ok === true || player !== null
  readonly property bool hasTrack: running && (title.length > 0 || artist.length > 0)
  readonly property bool isPlaying: status.ok === true
    ? status.state === "playing"
    : (player !== null && player.isPlaying === true)
  readonly property string title: String(status.title || (player ? player.trackTitle : "") || "")
  readonly property string artist: String(status.artist || (player ? player.trackArtist : "") || "")
  readonly property string album: String(status.album || (player ? player.trackAlbum : "") || "")

  // cliamp publishes no mpris:artUrl for anything, local or remote, so the cover is
  // derived from the Subsonic stream URL it does publish. The MPRIS value is still
  // preferred in case a future release starts sending one.
  // Held rather than recomputed to empty. The cover is derived from the stream path, so
  // any moment without a status, between tracks or while the socket changes owner,
  // would otherwise blank the artwork and flash the placeholder.
  property string artUrl: ""
  property int artSizePx: 300

  readonly property string resolvedArtUrl: {
    if (!running) return ""
    var fromMpris = player ? safeArtUrl(player.trackArtUrl) : ""
    if (fromMpris.length > 0) return fromMpris
    return safeArtUrl(Model.coverArtUrlFromStreamPath(status.path, artSizePx))
  }

  // Held only across the gap where cliamp is unreachable, which is the socket dropping
  // on a daemon restart. While it is running an empty value is the honest answer, so
  // radio and local files clear the cover instead of showing the last album played.
  onResolvedArtUrlChanged: if (running) artUrl = resolvedArtUrl

  readonly property real lengthSec: {
    if (status.durationSec > 0) return status.durationSec
    if (player && player.lengthSupported) return Number(player.length || 0)
    return 0
  }

  // Measured on 1.63.2: seeking a Navidrome track advances the queue instead of moving
  // within it, because these arrive as HTTP streams and cliamp cannot reposition one. A
  // duration is still known, so the bar is drawn, but it must not be interactive.
  readonly property bool hasProgress: running && lengthSec > 0
  readonly property bool canSeek: hasProgress && !isStream

  readonly property bool shuffle: status.shuffle === true
  readonly property string repeat: String(status.repeat || "Off")
  readonly property int total: Number(status.total || 0)
  readonly property real volumeDb: Number(status.volumeDb || 0)
  readonly property bool isStream: status.isStream === true

  // Ticked locally between MPRIS updates, because polling Position over D-Bus four
  // times a second is traffic for something the panel can count on its own.
  property real positionSec: 0
  property bool _askedAtEnd: false

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  // `omarchy bar set` stores a bare value as a string unless it is given --json, so the
  // documented way to flip one of these settings would otherwise be silently ignored.
  function boolSetting(name, fallback) {
    return Model.asBool(setting(name, fallback), fallback)
  }

  // Re-clamped on read so a hand-edited shell.json cannot poison the timer.
  function intSetting(name, fallback, min, max) {
    var value = parseInt(setting(name, fallback), 10)
    if (!isFinite(value)) value = fallback
    return Math.max(min, Math.min(max, value))
  }

  function findCliampPlayer() {
    var list = Mpris.players ? Mpris.players.values : []
    for (var i = 0; i < list.length; i++) {
      var p = list[i]
      if (!p) continue
      if (String(p.dbusName || "").indexOf("org.mpris.MediaPlayer2.cliamp") === 0) return p
    }
    return null
  }

  // Album art can be any string a tag supplies, so only these two schemes reach an Image.
  function safeArtUrl(raw) {
    var url = String(raw || "")
    if (url.indexOf("file://") === 0) return url
    if (url.indexOf("https://") === 0) return url
    return ""
  }

  // Held optimistically so the button flips on press instead of waiting for the poll,
  // then released as soon as cliamp reports the same thing.
  property int pendingPlaying: -1
  readonly property bool showPlaying: pendingPlaying === -1 ? isPlaying : pendingPlaying === 1

  function playPause() {
    pendingPlaying = isPlaying ? 0 : 1
    playHold.restart()
    if (sendOperation("toggle")) { settleTimer.restart(); return }
    if (running) player.togglePlaying()
  }

  // Never let an optimistic flip stick if cliamp disagrees.
  Timer {
    id: playHold
    interval: 2500
    repeat: false
    onTriggered: root.pendingPlaying = -1
  }

  function next() {
    if (sendOperation("next")) { settleTimer.restart(); return }
    if (running) player.next()
  }

  function previous() {
    if (sendOperation("prev")) { settleTimer.restart(); return }
    if (running) player.previous()
  }

  // Measured on 2.0.1: the socket seek takes a delta, not a position, whatever
  // `cliamp seek --help` says. The delta comes off the interpolated position rather than
  // the last polled one, which is up to a whole poll interval stale. MPRIS is the fallback.
  function seekTo(targetSec) {
    if (!canSeek) return
    var target = Math.max(0, Math.min(lengthSec, Number(targetSec) || 0))
    var delta = Math.round(target - positionSec)
    positionSec = target
    if (sendOperation("seek", { value: delta })) { settleTimer.restart(); return }
    if (player) player.seek(target - Number(player.position || 0))
  }

  function seekBy(deltaSec) { seekTo(positionSec + Number(deltaSec || 0)) }

  // cliamp speaks newline delimited JSON on its own socket, so status needs no
  // subprocess at all. One connection replaces a spawn every couple of seconds.
  readonly property string socketPath: (Quickshell.env("HOME") || "") + "/.config/cliamp/cliamp.sock"

  // cliamp 2 refuses anything but a version 2 request, and echoes the id back on every
  // reply. Nothing routes on the id, but two requests sharing one would be
  // indistinguishable. Measured on 2.0.1: the socket answers a version 1 request with
  // invalid_version, which is what left this panel showing nothing at all.
  property int requestSeq: 0

  function sendRequest(request) {
    if (!ipcConnected) return false
    request.version = 2
    request.id = "cliampui-" + (++requestSeq)
    ipcLoader.item.write(JSON.stringify(request) + "\n")
    ipcLoader.item.flush()
    return true
  }

  // Reads are methods answered in place. Anything that changes the player is an
  // operation answered with a job, and being accepted is all the acknowledgement a
  // command gets: the job's own outcome is never waited for.
  function sendMethod(method, extra) {
    var request = { method: method }
    if (extra) { for (var key in extra) request[key] = extra[key] }
    return sendRequest(request)
  }

  function sendOperation(operation, params) {
    var request = { operation: operation }
    if (params) request.params = params
    return sendRequest(request)
  }

  function refreshStatus() { sendMethod("state.get") }

  // cliamp resolves lyrics itself, from embedded tags then LRCLIB then NetEase, and
  // serves them on the same socket. Measured on 2.0.1: the lyrics operation answers with
  // a job whose result is {"ok":true,"lyrics":[{"start":30.23,"text":"..."}]}.
  property var lyrics: []
  property string lyricsTrackPath: ""

  readonly property bool hasLyrics: lyrics.length > 0
  // cliamp reports the position it has decoded to. Over A2DP the ears are about a
  // sixth of a second behind that, which is plainly visible against lyrics, so the
  // line is chosen from the position that has actually reached the sink.
  property int outputLatencyMs: 0
  readonly property int lyricTrimMs: intSetting("lyricTrimMs", 0, -1000, 1000)
  readonly property string latencyHelper: String(Qt.resolvedUrl("cliamp-output-latency")).replace("file://", "")

  function readOutputLatency() {
    if (latencyProcess.running) return
    latencyProcess.command = [latencyHelper]
    latencyProcess.running = true
  }

  Process {
    id: latencyProcess
    command: []
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.outputLatencyMs = Model.latencyMs(text)
    }
  }

  readonly property int activeLyricIndex: Model.activeLyricIndex(lyrics, positionSec - (outputLatencyMs + lyricTrimMs) / 1000)
  readonly property string activeLyric: activeLyricIndex >= 0
    ? String(lyrics[activeLyricIndex].text || "")
    : ""

  property string lyricsPendingPath: ""

  function refreshLyrics() {
    var path = String(status.path || "")
    if (path.length === 0) { lyrics = []; lyricsTrackPath = ""; return }
    if (path === lyricsTrackPath) return
    lyrics = []
    // One request outstanding at a time. The job carries no track, so the path the
    // single outstanding request was sent for is the only thing that can attribute it.
    if (lyricsPendingPath.length > 0) return
    // Marked fetched only once the request is actually out, or one dropped write
    // suppresses every retry for the rest of the track.
    if (sendOperation("lyrics")) {
      lyricsPendingPath = path
      lyricsTrackPath = path
      lyricsPollAttempts = 0
      lyricsTimeout.restart()
    }
  }

  // One dispatcher that knows what each operation's job means, because every terminal
  // job lands on this single hook. Lyrics, provider.tracks and load are waited on so a
  // row pick knows when the queue actually holds the playlist; everything else is
  // fire-and-forget like queue.play, whose acceptance is all a command needs.
  function acceptJob(job) {
    if (!job) return
    var operation = String(job.operation || "")
    if (operation === "lyrics") { root.acceptLyricsJob(job); return }
    if (operation === "provider.tracks") { root.acceptBrowseJob(job); return }
    if (operation === "load") { root.acceptLoadJob(job); return }
  }

  // The lyrics job is the one this panel used to wait on: it polls job.get until the
  // job is terminal, because a v2 operation answers with the job rather than the payload.
  property string lyricsJobId: ""
  property int lyricsPollAttempts: 0

  function acceptLyricsJob(job) {
    if (job.state === "queued" || job.state === "running") {
      if (job.id.length > 0) { lyricsJobId = job.id; lyricsPollTimer.restart() }
      return
    }
    lyricsJobId = ""
    lyricsPollTimer.stop()
    lyricsTimeout.stop()
    if (job.result.length > 0) { acceptLyrics(job.result); return }
    lyricsPendingPath = ""
    lyrics = []
  }

  // provider.tracks is an operation, so every page needs the same queued -> job.get
  // round as lyrics. A page is only adopted when its id is the one currently expected:
  // both reads clear _browsedJobId before sending, so a reply for the playlist we just
  // left can never be mistaken for the current read.
  function acceptBrowseJob(job) {
    if (job.state === "queued" || job.state === "running") {
      if (job.id.length > 0) { _browsedJobId = job.id; browsePollTimer.restart(); browseTimeout.restart() }
      return
    }
    browsePollTimer.stop()
    browseTimeout.stop()
    browsedLoading = false
    if (job.id.length === 0 || job.id !== _browsedJobId) return
    if (_browsedPlaylist !== browsedPlaylist) { _browsedJobId = ""; return }
    if (job.state === "succeeded") {
      var parsed = Model.parseProviderTracks(job.result, _browsedOffset)
      browsedTotal = parsed.total
      if (parsed.tracks.length > 0) {
        if (_browsedOffset === 0) browsedTracks = parsed.tracks
        else browsedTracks = root.browsedTracks.concat(parsed.tracks)
      }
      // Pull every remaining page so the list reads as complete rather than trailing
      // off; the loop is bounded by the total the first page reported.
      _browsedPageCount++
      if (root.browsedTracks.length < root.browsedTotal && _browsedPageCount < root._browsedMaxPages) {
        root.readMoreBrowsedTracks()
        _browsedJobId = ""
        return
      }
    }
    _browsedJobId = ""
  }

  // One poll per interval, and a hard stop after the same window as the timeout below,
  // so a job that never lands cannot leave a timer running for the rest of the track.
  Timer {
    id: lyricsPollTimer
    interval: 400
    repeat: true
    onTriggered: {
      if (root.lyricsJobId.length === 0 || root.lyricsPollAttempts >= 12) {
        root.lyricsJobId = ""
        stop()
        return
      }
      root.lyricsPollAttempts++
      root.sendMethod("job.get", { job_id: root.lyricsJobId })
    }
  }

  // cliamp answers every request, so this only fires when a reply arrives in a shape the
  // router does not recognise. Only the slot is freed: the track keeps its fetched mark,
  // so one lost reply costs that track its lyrics rather than a request every 5 seconds.
  Timer {
    id: lyricsTimeout
    interval: 5000
    repeat: false
    onTriggered: {
      root.lyricsPendingPath = ""
      root.lyricsJobId = ""
      lyricsPollTimer.stop()
    }
  }

  // ---- playlist loading (which playlist the queue holds) ----

  // The daemon's snapshot never names the playlist it is on, so the name is only
  // known from the loads this panel runs, or from a size match against the list.
  property string loadedPlaylist: ""
  // A load's job, polled once so a row pick can fire queue.play at the right instant
  // instead of hoping a future status will make the playlist visible.
  property string _loadJobId: ""
  property int loadPollAttempts: 0
  // The name the single outstanding load was asked for; the job itself carries none.
  property string _loadPlaylist: ""

  Timer {
    id: loadPollTimer
    interval: 400
    repeat: true
    onTriggered: {
      if (root._loadJobId.length === 0 || root.loadPollAttempts >= 20) {
        root._loadJobId = ""
        stop()
        return
      }
      root.loadPollAttempts++
      root.sendMethod("job.get", { job_id: root._loadJobId })
    }
  }

  Timer {
    id: loadTimeout
    interval: 8000
    repeat: false
    onTriggered: {
      root._loadJobId = ""
      loadPollTimer.stop()
    }
  }

  function acceptLoadJob(job) {
    if (job.state === "queued" || job.state === "running") {
      if (job.id.length > 0) { _loadJobId = job.id; loadPollTimer.restart(); loadTimeout.restart() }
      return
    }
    loadPollTimer.stop()
    loadTimeout.stop()
    _loadJobId = ""
    if (job.state === "succeeded") {
      root.loadedPlaylist = String(root._loadPlaylist || "")
      // The load starts playing on its own; only a row the user double-clicked is
      // repointed, so the queue can land on the exact index instead of track zero.
      if (root.pendingJump && String(root.pendingJump.playlist || "") === String(root.loadedPlaylist || "")) {
        if (root.sendOperation("queue.play", { index: root.pendingJump.index })) {
          root.pendingJump = null
          root.pendingJumpTimer.stop()
          root.settleTimer.restart()
        }
      }
      return
    }
    // A load that failed cannot reach the row the jump pointed at, so the jump has no
    // future here: without this the pendingJump timeout would only clear it later.
    root.pendingJump = null
    root.pendingJumpTimer.stop()
  }

  // Learnt by size when the panel connects to an already-playing daemon: the loaded
  // playlist's count is exactly the queue's total. Ambiguous counts leave it unknown.
  function detectLoadedPlaylist() {
    if (root.loadedPlaylist.length > 0) return root.loadedPlaylist
    if (root.total <= 0 || root.playlists.length === 0) return ""
    var found = ""
    for (var i = 0; i < root.playlists.length; i++) {
      if (Number(root.playlists[i].count) === root.total) {
        if (found.length > 0) return ""
        found = String(root.playlists[i].name || "")
      }
    }
    if (found.length > 0) root.loadedPlaylist = found
    return root.loadedPlaylist
  }

  // ---- playlist browsing (the song list) ----

  property string browsedPlaylist: ""
  property var browsedTracks: []
  property int browsedTotal: 0
  property bool browsedLoading: false
  // A cross-playlist jump: {playlist, index}. Set when the row is not on the current
  // queue, released the moment the status agrees the playlist is loaded with rows.
  property var pendingJump: null
  // The single provider.tracks page currently being waited on, plus the playlist and
  // offset it was asked for, so a late page cannot land in a newer list.
  property string _browsedJobId: ""
  property int _browsedOffset: 0
  property string _browsedPlaylist: ""
  property int browsePollAttempts: 0
  // Pages fetched for the current browsed playlist, capped so a very large playlist
  // cannot page-fill the panel forever.
  property int _browsedPageCount: 0
  readonly property int _browsedMaxPages: 50

  // A page is mostly a server round trip, so the poll cap is wider than lyrics'.
  Timer {
    id: browsePollTimer
    interval: 400
    repeat: true
    onTriggered: {
      if (root._browsedJobId.length === 0 || root.browsePollAttempts >= 20) {
        root._browsedJobId = ""
        root.browsedLoading = false
        stop()
        return
      }
      root.browsePollAttempts++
      root.sendMethod("job.get", { job_id: root._browsedJobId })
    }
  }

  Timer {
    id: browseTimeout
    interval: 8000
    repeat: false
    onTriggered: {
      root._browsedJobId = ""
      root.browsedLoading = false
      browsePollTimer.stop()
    }
  }

  Timer {
    id: pendingJumpTimer
    interval: 4000
    repeat: false
    // A load that never reports the target playlist must not leave a ghost jump for a
    // later, unrelated status update to fire.
    onTriggered: root.pendingJump = null
  }

  function readPlaylistTracks(name) {
    var playlist = String(name || "")
    root.browsedPlaylist = playlist
    root._browsedPlaylist = playlist
    root.browsedTracks = []
    root.browsedTotal = 0
    root.browsedLoading = false
    root._browsedJobId = ""
    root._browsedOffset = 0
    root._browsedPageCount = 0
    browsePollTimer.stop()
    browseTimeout.stop()
    if (playlist.length === 0) return
    if (root.sendOperation("provider.tracks", { provider: "local", playlist: playlist, offset: 0, limit: 200 })) {
      root.browsePollAttempts = 0
      root.browsedLoading = true
      browseTimeout.restart()
    }
  }

  function readMoreBrowsedTracks() {
    if (root.browsedLoading) return
    if (root.browsedPlaylist.length === 0) return
    if (root.browsedTracks.length >= root.browsedTotal) return
    root._browsedOffset = root.browsedTracks.length
    root._browsedJobId = ""
    if (root.sendOperation("provider.tracks", { provider: "local", playlist: root.browsedPlaylist, offset: root._browsedOffset, limit: 200 })) {
      root.browsePollAttempts = 0
      root.browsedLoading = true
      browseTimeout.restart()
    }
  }

  // One row is answered twice by the socket: the op is accepted as a queued job, and
  // the same reply's queued state comes back before any status. Only the current id is
  // adopted, so no stale poll can land in a list that has already moved on.
  function clearBrowseRequest() {
    root._browsedJobId = ""
    root.browsedLoading = false
    browsePollTimer.stop()
    browseTimeout.stop()
  }

  function playBrowsedTrack(row) {
    if (!row) return
    var playlist = String(root.browsedPlaylist || "")
    if (playlist.length === 0) return
    // Already known to hold this playlist: pointing the queue at the row is enough,
    // and avoids load restarting from track zero for a moment. The daemon reports no
    // playlist name, so "loaded" is the name learned from a load or a size match.
    if (String(root.loadedPlaylist || "") === playlist && root.total > 0) {
      root.sendOperation("queue.play", { index: row.index })
      root.settleTimer.restart()
      return
    }
    root.pendingJump = { playlist: playlist, index: row.index }
    root.pendingJumpTimer.restart()
    if (root.sendOperation("load", { playlist: playlist })) {
      root._loadPlaylist = playlist
      root.settleTimer.restart()
      return
    }
    root.pendingJump = null
    root.pendingJumpTimer.stop()
  }

  function clearPendingJump() {
    root.pendingJump = null
    root.pendingJumpTimer.stop()
  }

  // The first playlist the panel sees on open, or the one currently loaded, becomes the
  // browsed one so the summary and list are never empty. Called later than the playlist
  // fetch, since `cliamp playlist list` answers after the panel has already opened.
  function ensureBrowsedDefault() {
    if (root.browsedPlaylist.length > 0) return
    if (root.detectLoadedPlaylist().length > 0) {
      root.readPlaylistTracks(root.detectLoadedPlaylist())
      return
    }
    if (root.playlists.length === 0) return
    // Prefer a playlist that holds tracks so the list is never a bare pick hint.
    var first = ""
    for (var i = 0; i < root.playlists.length; i++) {
      if (Number(root.playlists[i].count) > 0) { first = String(root.playlists[i].name || ""); break }
    }
    if (first.length === 0) first = String(root.playlists[0].name || "")
    if (first.length > 0) root.readPlaylistTracks(first)
  }

  // A reply lost with the connection is worth asking for again, and only that case is.
  function dropLyricsRequest() {
    if (lyricsPendingPath.length === 0) return
    lyricsPendingPath = ""
    lyricsJobId = ""
    lyricsPollTimer.stop()
    lyricsTrackPath = ""
  }

  function acceptLyrics(raw) {
    var wanted = lyricsPendingPath
    lyricsPendingPath = ""
    lyricsJobId = ""
    lyricsPollTimer.stop()
    lyricsTimeout.stop()
    if (wanted === String(status.path || "")) { lyrics = Model.parseLyrics(raw); return }
    // The track changed while this was in flight, so it answers a question nobody is
    // asking now. Re-arm and ask again for whatever is playing.
    lyricsTrackPath = ""
    refreshLyrics()
  }

  function syncPosition() {
    if (status.ok === true) positionSec = Number(status.positionSec || 0)
    else if (player && player.positionSupported) positionSec = Number(player.position || 0)
    if (panelOpen) refreshStatus()
  }

  // The socket changes owner whenever the daemon relaunches or hands over to an
  // interactive session. Measured on Quickshell 0.3.0: one connect against a missing
  // path (ServerNotFoundError) bricks a Socket for good, and no later write to
  // connected or path ever tries again, so every retry has to be a brand new Socket.
  readonly property bool ipcConnected: !!(ipcLoader.item && ipcLoader.item.connected)

  Loader {
    id: ipcLoader
    active: true
    sourceComponent: Socket {
      path: root.socketPath
      connected: true

      // On connect ask for status at once; on drop abandon what it was in flight for.
      onConnectionStateChanged: {
        if (connected) { root.refreshStatus(); return }
        root.dropLyricsRequest()
        root.clearBrowseRequest()
      }

      parser: SplitParser {
        splitMarker: "\n"
        onRead: function (line) {
          var raw = String(line || "")
          var kind = Model.messageKind(raw)
          // Every command answers on this socket too, as a job. A job carries no track,
          // so parsing one as a status blanked the panel until the next poll; the lyrics
          // job is the only one whose result the panel waits for. A refusal is the only
          // report a command ever gets.
          if (kind === "job") { root.acceptJob(Model.jobInfo(raw)); return }
          if (kind === "error") { root.lastError = Model.ackError(raw); root.clearPendingJump(); return }
          if (kind !== "status") return
          var parsed = Model.parseStatus(raw)
          root.status = parsed
          root.lastError = parsed.ok ? "" : parsed.lastError
          // The feed carries position, so the local tick only fills the gaps between polls.
          if (parsed.ok) root.positionSec = Number(parsed.positionSec || 0)
        }
      }
    }
  }

  Timer {
    id: reconnectTimer
    interval: 700
    repeat: true
    // No assignment to running anywhere: the binding is the only thing that can stop
    // this, so a later disconnect can always start it again.
    running: !root.ipcConnected
    onTriggered: {
      if (root.ipcConnected) return
      ipcLoader.active = false
      ipcLoader.active = true
    }
    onRunningChanged: {
      if (running) goneTimer.restart()
      else goneTimer.stop()
    }
  }

  // The socket drops briefly whenever the daemon restarts. Blanking the artwork and
  // title for that window is worse than briefly showing the last known track, so the
  // state is only cleared once cliamp has genuinely stayed away.
  Timer {
    id: goneTimer
    interval: 6000
    repeat: false
    onTriggered: {
      if (root.ipcConnected) return
      root.status = Model.defaultStatus()
      root.artUrl = ""
    }
  }

  // cliamp's own 10 band spectrum, the same feed its first-party widget draws. visstream
  // holds one IPC connection open and emits a frame per tick, which the docs give as the
  // way to consume it from a UI toolkit. It runs only while the popup is open and
  // playing, so a shut panel costs nothing.
  property var bands: []

  Process {
    id: visProcess
    command: [root.cliampPath, "visstream", "--fps", "20"]
    running: root.panelOpen && root.isPlaying
    stdout: SplitParser {
      splitMarker: "\n"
      onRead: function (line) {
        var frame = Model.parseBands(line)
        if (frame.length > 0) root.bands = frame
      }
    }
    onRunningChanged: if (!running) root.bands = []
  }

  Timer {
    id: statusTimer
    interval: root.statusIntervalMs
    repeat: true
    running: root.wantsStatus && root.ipcConnected
    triggeredOnStart: true
    onTriggered: root.refreshStatus()
  }

  Timer {
    id: positionTimer
    interval: 250
    repeat: true
    running: root.panelOpen && root.isPlaying
    onTriggered: {
      var next = root.positionSec + interval / 1000
      // A repeat restarts the track without MPRIS reporting a track change, so the
      // position is asked for at the end rather than clamped and left stale. Asked
      // once, because a duration shorter than the audio would poll four times a
      // second for the rest of the track.
      if (root.lengthSec > 0 && next >= root.lengthSec) {
        if (!root._askedAtEnd) { root._askedAtEnd = true; root.refreshStatus() }
        return
      }
      root._askedAtEnd = false
      root.positionSec = next
    }
  }

  Connections {
    target: root.player
    ignoreUnknownSignals: true
    function onTrackChanged() { root.syncPosition() }
    function onPlaybackStateChanged() { root.syncPosition() }
    function onSeek() { root.syncPosition() }
  }

  onPanelOpenChanged: {
    if (!panelOpen) return
    syncPosition()
    readSinkRate()
    readOutputLatency()
    readSinkAvailability()
    readPlaylists()
    readLibrary()
    // The song list picks its first playlist here so it is populated for the first
    // open; cliamp playlist list answers a beat later and defaults it in its finish.
    ensureBrowsedDefault()
  }

  // ---- PipeWire routing and the signal verdict ----

  // Rebuilt from an explicit signal rather than left as a binding on values: a list
  // mutating in place does not re-evaluate the binding, so a device connected after
  // the panel loaded never appeared. Same hazard as the MPRIS player lookup.
  property var nodes: []

  function rebuildNodes() {
    nodes = Pipewire.nodes ? (Pipewire.nodes.values || []) : []
    readSinkAvailability()
  }

  Connections {
    target: Pipewire.nodes
    ignoreUnknownSignals: true
    function onValuesChanged() { root.rebuildNodes() }
  }

  property var sinkAvailability: ({})

  // Filtered through the stock helper the first-party audio panel uses, so an output
  // with nothing plugged into it is never offered as somewhere to send music.
  readonly property var sinks: {
    // Depends on nodes, which is now replaced wholesale on every change.
    var list = []
    for (var i = 0; i < nodes.length; i++) {
      var n = nodes[i]
      if (!n || !n.isSink || n.isStream) continue
      var known = sinkAvailability[String(n.name || "")]
      if (known === false) continue
      list.push(n)
    }
    return list
  }

  function readSinkAvailability() {
    if (availabilityProcess.running) return
    availabilityProcess.running = true
  }

  Process {
    id: availabilityProcess
    command: ["omarchy-audio-sink-availability"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.sinkAvailability = Model.parseSinkAvailability(text)
    }
  }

  // cliamp reaches PipeWire through the ALSA compatibility layer, so its stream
  // announces itself as "PipeWire ALSA [cliamp]" rather than as a native client.
  readonly property var streamNode: {
    for (var i = 0; i < nodes.length; i++) {
      var n = nodes[i]
      if (!n || !n.isStream || !n.properties) continue
      if (String(n.properties["application.name"] || "").indexOf("cliamp") >= 0) return n
    }
    return null
  }

  readonly property var peakNode: streamNode

  // Read from the global link list rather than a PwNodeLinkTracker, which reports no
  // groups at all for this stream. Taken live rather than cached, so a sink that
  // disappears cannot leave a dead device name sitting in the panel.
  readonly property var currentSink: {
    if (!streamNode) return null
    var groups = Pipewire.linkGroups ? (Pipewire.linkGroups.values || []) : []
    for (var i = 0; i < groups.length; i++) {
      var g = groups[i]
      if (!g || !g.source || !g.target) continue
      if (g.source.id !== streamNode.id) continue
      // cliamp is also linked to quickshell itself for the peak meter, and that
      // tap is not a sink, so the isSink test is what keeps the route honest.
      if (g.target.isSink) return g.target
    }
    return null
  }


  readonly property string currentSinkLabel: currentSink
    ? String(currentSink.description || currentSink.nickname || currentSink.name || "")
    : ""

  readonly property int streamRate: streamNode ? Model.rateFromNodeProps(streamNode.properties) : 0
  property int sinkRate: 0

  readonly property string codec: codecFromPath(status.path)
  // A Subsonic URL is judged by whether cliamp asked for format=raw. A local file is
  // judged by its container, since nothing re-encoded it on the way in.
  readonly property bool transcoded: status.path.indexOf("/rest/stream") >= 0
    ? Model.transcodedFromPath(status.path)
    : (codec === "MP3" || codec === "OGG" || codec === "OPUS")
  // Any attenuation alters samples, so only an exact 0 dB counts. Setting volume over
  // MPRIS lands on -0.02 dB, which really is not unity and must not pass.
  readonly property bool playerUnity: Math.abs(volumeDb) < 0.001
  readonly property bool unityGain: playerUnity
    && (!hasStreamVolume || (!streamMuted && Math.abs(streamVolume - 1) < 0.001))
  readonly property bool eqFlat: status.eqFlat !== false

  // Empty for anything wired, so the lossy-link branch only fires on real Bluetooth.
  readonly property string lossyLink: currentSink
    ? Model.bluetoothCodecLabel(currentSink.properties)
    : ""

  readonly property var signalVerdict: Model.verdict({
    streamRate: streamRate,
    sinkRate: sinkRate,
    unityGain: unityGain,
    playerUnity: playerUnity,
    eqFlat: eqFlat,
    transcoded: transcoded,
    codec: codec,
    requestedRate: forcedRate,
    sourceRate: sourceRate,
    lossyLink: lossyLink
  }, root.strings.verdict)

  function codecFromPath(path) {
    var text = String(path || "")
    var cut = text.indexOf("?")
    if (cut >= 0) text = text.slice(0, cut)
    var dot = text.lastIndexOf(".")
    if (dot < 0) return ""
    var ext = text.slice(dot + 1).toUpperCase()
    if (ext === "MP3" || ext === "FLAC" || ext === "WAV" || ext === "ALAC"
      || ext === "OGG" || ext === "OPUS") return ext
    return ""
  }

  PwObjectTracker { objects: root.sinks }
  PwObjectTracker { objects: root.streamNode ? [root.streamNode] : [] }

  // The verdict is only ever derived from what the sink actually adopted, never from
  // the rate that was requested, because an unsupported rate silently lands on the
  // nearest one the DAC does support. No PipeWire property reports this.
  function readSinkRate() {
    if (sinkRateProcess.running) return
    sinkRateProcess.command = ["pactl", "list", "short", "sinks"]
    sinkRateProcess.running = true
  }

  Process {
    id: sinkRateProcess
    command: []
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var wanted = root.currentSink ? String(root.currentSink.name || "") : ""
        var lines = String(text || "").split("\n")
        for (var i = 0; i < lines.length; i++) {
          if (wanted.length > 0 && lines[i].indexOf(wanted) < 0) continue
          var rate = Model.sinkRateFromPactl(lines[i])
          if (rate > 0) { root.sinkRate = rate; return }
        }
        root.sinkRate = 0
      }
    }
  }

  // The graph takes a moment to settle after a forced rate, so the readback waits.
  Timer {
    id: rateSettleTimer
    interval: 2000
    repeat: false
    onTriggered: { root.readSinkRate(); root.readOutputLatency() }
  }

  // ---- rate following ----

  readonly property bool followSourceRate: boolSetting("followSourceRate", true)
  property int forcedRate: 0

  function matchRate() {
    if (streamRate <= 0 || rateProcess.running) return
    if (forcedRate === streamRate) return
    rateProcess.command = ["pw-metadata", "-n", "settings", "0", "clock.force-rate", String(streamRate)]
    rateProcess.running = true
    forcedRate = streamRate
    rateSettleTimer.restart()
  }

  function releaseRate() {
    if (forcedRate === 0 || rateProcess.running) return
    rateProcess.command = ["pw-metadata", "-n", "settings", "0", "clock.force-rate", "0"]
    rateProcess.running = true
    forcedRate = 0
    rateSettleTimer.restart()
  }

  Process { id: rateProcess; command: [] }

  // Following is deliberately scoped to actual playback: a forced rate reaches every
  // application on the box, so it is released the moment the music stops.
  // One handler only: QML rejects a second onIsPlayingChanged and the whole component
  // then fails to load, which takes the widget out of the bar entirely.
  onIsPlayingChanged: {
    if (pendingPlaying !== -1 && isPlaying === (pendingPlaying === 1)) pendingPlaying = -1
    if (!followSourceRate) return
    if (isPlaying) matchRate()
    else releaseRate()
  }

  // A sink change means the old rate reading describes a device no longer in the path,
  // and the switch can happen outside this panel, so the readback is not tied to a click.
  onCurrentSinkChanged: {
    if (followSourceRate && isPlaying) matchRate()
    rateSettleTimer.restart()
  }

  onStreamRateChanged: {
    if (followSourceRate && isPlaying) matchRate()
    else rateSettleTimer.restart()
    // The node is destroyed and remade by a daemon relaunch, so this always fires
    // after one. That re-check is what settles a track change that happened while
    // the relaunch helper was still running and its change event was swallowed.
    considerNativeRate()
  }

  Component.onDestruction: releaseRate()

  // ---- actions ----

  property var playlists: []
  property var results: []
  property string libraryQuery: ""

  // Server rows on their own. Saved playlists are matched locally and merged in front,
  // so a playlist list arriving late does not need a second server round trip.
  property var _libraryRows: []

  readonly property string libraryHelper: String(Qt.resolvedUrl("cliamp-library")).replace("file://", "")

  function _recomputeResults() {
    results = Model.matchPlaylists(playlists, libraryQuery).concat(_libraryRows)
  }

  // The query this helper run was dispatched for, so a keystroke that arrives while
  // one is in flight is not silently dropped and does not leave stale rows on screen.
  property string _dispatchedQuery: ""

  // The library is browsed straight off the Subsonic server using the token cliamp
  // already published, so picking something never has to stop the daemon.
  function readLibrary() { _dispatchLibrary() }

  function search(query) {
    libraryQuery = String(query || "")
    _recomputeResults()
    _dispatchLibrary()
  }

  // One dispatcher, so a refresh cannot quietly replace an active search with the
  // full album list while the playlist rows are still filtered by the query.
  function _dispatchLibrary() {
    if (albumProcess.running) return
    _dispatchedQuery = libraryQuery
    albumProcess.command = libraryQuery.length > 0
      ? [libraryHelper, "search", libraryQuery]
      : [libraryHelper, "albums", "200"]
    albumProcess.running = true
  }

  function playResult(item) {
    if (!item) return
    if (item.kind === "playlist") {
      // The song list below follows the Library's pick: point it at the playlist and
      // fetch its rows first, then hand the name to the daemon to load and play.
      root.readPlaylistTracks(String(item.name))
      loadPlaylist(String(item.name))
      return
    }
    if (albumPlayProcess.running || !item.id) return
    albumPlayProcess.command = [libraryHelper,
      item.kind === "song" ? "play-song" : "play", String(item.id)]
    albumPlayProcess.running = true
  }

  Process {
    id: albumProcess
    command: []
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root._libraryRows = Model.parseResults(text)
        root._recomputeResults()
      }
    }
    onExited: if (root._dispatchedQuery !== root.libraryQuery) root._dispatchLibrary()
  }

  Process {
    id: albumPlayProcess
    command: []
    onExited: settleTimer.restart()
  }

  function readPlaylists() {
    if (playlistProcess.running) return
    playlistProcess.command = [cliampPath, "playlist", "list"]
    playlistProcess.running = true
  }

  Process {
    id: playlistProcess
    command: []
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.playlists = Model.parsePlaylists(text)
        root._recomputeResults()
        root.ensureBrowsedDefault()
      }
    }
  }

  // Loading a saved playlist is the only way a headless daemon can reach a Navidrome
  // library: the playlist keeps resolved stream URLs, and the browser is TUI only.
  // Measured: load starts playing on its own, so nothing follows it here. The play that
  // used to be sent 700 ms later was the only delayed action in the plugin.
  function loadPlaylist(name) {
    if (!name) return
    if (sendOperation("load", { playlist: String(name) })) {
      root._loadPlaylist = String(name)
      settleTimer.restart()
      return
    }
    if (actionProcess.running) return
    actionProcess.command = [cliampPath, "load", String(name)]
    actionProcess.running = true
    settleTimer.restart()
  }

  // Volume is cliamp's PipeWire stream volume, moved exactly the way the stock audio
  // panel moves a sink: a property on a tracked node, pushed both ways, so a drag has
  // no subprocess and no poll behind it to fight. cliamp's own gain stays at unity.
  readonly property real streamVolume: streamNode && streamNode.audio ? streamNode.audio.volume : 0
  readonly property bool streamMuted: !!(streamNode && streamNode.audio && streamNode.audio.muted)
  readonly property bool hasStreamVolume: !!(streamNode && streamNode.audio)

  // A level the operator sets is one they expect to hear, so setting one clears mute.
  function setStreamVolume(value) {
    if (!streamNode || !streamNode.audio) return
    streamNode.audio.muted = false
    streamNode.audio.volume = Math.max(0, Math.min(1, Number(value) || 0))
  }

  function setDevice(name) {
    if (actionProcess.running || !name) return
    actionProcess.command = [cliampPath, "device", String(name)]
    actionProcess.running = true
  }

  // Measured against the socket: cliamp's shuffle and repeat operations ignore every
  // parameter that might name a target state and simply toggle or cycle on each call,
  // so a target mode is reached by advancing each channel the right number of steps
  // from the last status the panel saw. Every step in a burst applies exactly one state
  // change whichever order it lands in, so a burst always ends on the requested mode.

  function setRepeatMode(target) {
    var order = ["Off", "All", "One"]
    var current = String(root.repeat || "Off")
    var ci = order.indexOf(current); if (ci < 0) ci = 0
    var ti = order.indexOf(target); if (ti < 0) ti = 0
    var steps = (ti - ci + order.length) % order.length
    for (var i = 0; i < steps; i++) root.sendOperation("repeat")
  }

  function setShuffleMode(wanted) {
    if (wanted === root.shuffle) return
    root.sendOperation("shuffle")
  }

  // The four modes are one exclusive group: selecting one clears the others, which is
  // what the icon row in the transport shows. "sequential" means shuffle off, repeat off;
  // the daemon's status is the only source of truth for what is selected afterwards.
  function selectMode(mode) {
    if (mode === "shuffle") { setRepeatMode("Off"); setShuffleMode(true) }
    else if (mode === "repeatAll") { setShuffleMode(false); setRepeatMode("All") }
    else if (mode === "repeatOne") { setShuffleMode(false); setRepeatMode("One") }
    else { setShuffleMode(false); setRepeatMode("Off") }
    settleTimer.restart()
  }

  // Keyboard mapping: s alternates sequential and shuffle; r walks the repeat side of
  // the exclusive group, sequential -> list -> one -> sequential.
  function selectKey(which) {
    if (which === "shuffle") {
      if (root.shuffle) selectMode("sequential")
      else selectMode("shuffle")
      return
    }
    var current = root.shuffle ? "shuffle" : String(root.repeat || "Off")
    var next = (current === "shuffle" || current === "Off") ? "repeatAll"
      : current === "All" ? "repeatOne" : "sequential"
    selectMode(next)
  }

  // cliamp cannot attach to a running instance, so the helper stops the daemon for
  // the life of the terminal session and starts it again afterwards. Without that,
  // opening the player spawns a second copy that the panel cannot see.
  property int sourceRate: 0

  readonly property bool followNativeRate: boolSetting("followNativeRate", false)
  readonly property string nativeRateHelper: String(Qt.resolvedUrl("cliamp-daemon-rate-apply")).replace("file://", "")
  // The rate already asked for, so an output the hardware or cliamp refuses is not
  // requested again in a loop on every status poll.
  property int attemptedNativeRate: 0
  readonly property string sourceRateHelper: String(Qt.resolvedUrl("cliamp-source-rate")).replace("file://", "")

  // Resolved per track, because cliamp exposes no source rate of its own.
  property string sourceRateTrackPath: ""

  function readSourceRate() {
    if (sourceRateProcess.running) return
    var path = String(status.path || "")
    if (path.length === 0) { sourceRate = 0; sourceRateTrackPath = ""; return }
    // Status is reassigned on every poll, so without this the helper queried the
    // server every couple of seconds for a rate that only changes with the track.
    if (path === sourceRateTrackPath) return
    sourceRateTrackPath = path
    sourceRateProcess.command = [sourceRateHelper, path]
    sourceRateProcess.running = true
  }

  Process {
    id: sourceRateProcess
    command: []
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var value = parseInt(String(text || "").trim(), 10)
        root.sourceRate = isFinite(value) && value > 0 ? value : 0
      }
    }
  }

  // One handler only. A second onStatusChanged in this object is "Property value set
  // multiple times", which fails the whole Service and removes the widget from the bar.
  onStatusChanged: {
    if (!wantsStatus) return
    root.detectLoadedPlaylist()
    readSourceRate()
    // Nobody reads lyrics behind a shut panel, so that half stays panel only.
    if (panelOpen) refreshLyrics()
    // A load answered by pointing the queue at the row the user picked, once. This is
    // where the pendingJump is replayed because it is the single onStatusChanged this
    // component is allowed; the load job itself usually answers first, so this guard
    // uses the name the load reported rather than the snapshot's absent playlist field.
    if (root.pendingJump) {
      if (String(root.loadedPlaylist || "") === String(root.pendingJump.playlist || "") && root.total > 0) {
        if (root.sendOperation("queue.play", { index: root.pendingJump.index })) {
          root.pendingJump = null
          if (root.pendingJumpTimer) root.pendingJumpTimer.stop()
          root.settleTimer.restart()
        }
      }
    }
  }

  // Relaunching cliamp is the only way to change its output rate, so this is gated
  // hard: only while the daemon itself is what is running, only when the file really
  // differs, and never twice for the same rate.
  onSourceRateChanged: considerNativeRate()

  function considerNativeRate() {
    if (!followNativeRate) return
    if (nativeRateProcess.running) return
    if (sourceRate <= 0 || streamRate <= 0) return
    if (Math.abs(sourceRate - streamRate) <= 1) { attemptedNativeRate = 0; return }
    // 88.2 and 176.4 kHz are not accepted output rates, so relaunching would land on
    // the default and gap the audio for nothing.
    if (!Model.isSupportedOutputRate(sourceRate)) return
    if (attemptedNativeRate === sourceRate) return
    attemptedNativeRate = sourceRate
    nativeRateProcess.command = [nativeRateHelper, String(sourceRate)]
    nativeRateProcess.running = true
  }

  Process {
    id: nativeRateProcess
    command: []
    // Re-check on exit as well: a track change during the relaunch is swallowed by
    // the running guard, and the stream node can settle before or after this exit,
    // so both this and onStreamRateChanged re-evaluate and the guards dedupe them.
    onExited: { settleTimer.restart(); root.considerNativeRate() }
  }

  // cliamp allows one instance per user, so waking is only offered while nothing owns
  // the socket. The sandboxed unit ships with the plugin and is preferred; without it
  // the same entry script, which reads the sample-rate pin the native-rate relaunch
  // writes, is run detached instead. The reconnect loop picks the daemon up as soon as
  // it owns the socket, so nothing here needs a terminal.
  readonly property string daemonEntryScript: String(Qt.resolvedUrl("cliamp-daemon-start")).replace("file://", "")

  function wakeDaemon() {
    if (running) return "running"
    wakeEnableCheck.command = ["systemctl", "--user", "is-enabled", "cliamp-daemon.service"]
    wakeEnableCheck.running = true
    return "requested"
  }

  Process {
    id: wakeEnableCheck
    onExited: function (exitCode) {
      if (exitCode === 0) {
        Quickshell.execDetached(["systemctl", "--user", "start", "cliamp-daemon.service"])
      } else {
        Quickshell.execDetached(["/bin/bash", root.daemonEntryScript])
      }
    }
  }

  Process {
    id: actionProcess
    command: []
    // A cliamp verb takes a moment to land, so the panel re-reads rather than guessing.
    onExited: settleTimer.restart()
  }

  Timer {
    id: settleTimer
    interval: 400
    repeat: false
    onTriggered: {
      root.refreshStatus()
      root.readSinkRate()
    }
  }
}
