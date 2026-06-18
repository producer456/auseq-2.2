import SwiftUI

/// Arranger — tracks as lanes on one shared, zoomable/scrollable bar timeline.
/// Gestures: pinch = zoom, 1-finger drag = scroll, tap = move playhead,
/// long-press+drag = select (or set the loop region on the ruler).
struct ArrangeView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var seq: Sequencer
    var onEditTracks: () -> Void = {}   // open full per-track controls

    private let headerWidth: CGFloat = 116
    private let laneHeight: CGFloat = 46
    private let rulerHeight: CGFloat = 28
    private let loPitch = 24, hiPitch = 96
    private let minPPB: CGFloat = 5, maxPPB: CGFloat = 160

    @State private var ppb: CGFloat = 0            // points per beat; 0 = fit to width
    @State private var pinchStartPPB: CGFloat?
    @State private var selectMode = false          // marquee tool: drag selects/sets loop instead of scrolling

    private var totalBeats: Int { max(1, seq.loopBars * seq.beatsPerBar) }

    var body: some View {
        GeometryReader { outer in
            let timelineVis = max(60, outer.size.width - headerWidth)
            let effPPB = ppb > 0 ? ppb : max(minPPB, timelineVis / CGFloat(totalBeats))
            let contentW = CGFloat(totalBeats) * effPPB

            VStack(spacing: 0) {
                editToolbar
                Divider().overlay(Theme.gold.opacity(0.3))

                ScrollView(.vertical) {
                    HStack(alignment: .top, spacing: 0) {
                        // Fixed header column
                        VStack(spacing: 4) {
                            rulerHeaderCell.frame(height: rulerHeight)
                            ForEach(model.tracks) { track in
                                LaneHeaderView(track: track, isSelected: track.id == model.selectedTrackID,
                                               onSelect: { model.select(track) },
                                               onEdit: onEditTracks)
                                    .frame(width: headerWidth, height: laneHeight)
                            }
                            Button { model.addTrack() } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: "plus").font(.system(size: 12, weight: .bold))
                                    Text("ADD TRACK").etchedLabel(8, weight: .bold)
                                }
                                .foregroundStyle(Theme.orange)
                                .frame(width: headerWidth, height: 30)
                                .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.25)))
                                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.gold.opacity(0.4)))
                            }
                        }
                        .frame(width: headerWidth)

                        // Zoom/scroll timeline column
                        ScrollView(.horizontal) {
                            VStack(spacing: 4) {
                                RulerTimeline(seq: seq, totalBeats: totalBeats, selectMode: selectMode,
                                              selectedTrackID: model.selectedTrackID)
                                    .frame(width: contentW, height: rulerHeight)
                                ForEach(model.tracks) { track in
                                    LaneTimelineView(track: track, seq: seq, totalBeats: totalBeats,
                                                     loPitch: loPitch, hiPitch: hiPitch,
                                                     onSelect: { model.select(track) })
                                        .frame(width: contentW, height: laneHeight)
                                }
                            }
                            .gesture(
                                MagnificationGesture()
                                    .onChanged { scale in
                                        if pinchStartPPB == nil { pinchStartPPB = effPPB }
                                        ppb = min(maxPPB, max(minPPB, (pinchStartPPB ?? effPPB) * scale))
                                    }
                                    .onEnded { _ in pinchStartPPB = nil }
                            )
                        }
                        .scrollDisabled(selectMode)   // let drags select/set-loop instead of scrolling
                    }
                }
            }
            .background(Theme.rail.opacity(0.5))
        }
    }

    private var rulerHeaderCell: some View {
        HStack(spacing: 6) {
            Text(seq.hasLoopRegion ? "LOOP" : "BARS")
                .etchedLabel(9, soft: !seq.hasLoopRegion, weight: .bold)
                .foregroundStyle(seq.hasLoopRegion ? Theme.orange : Theme.etchedSoft)
            if seq.hasLoopRegion {
                Button { seq.clearLoopRegion() } label: {
                    Image(systemName: "xmark.circle.fill").font(.caption).foregroundStyle(Theme.etchedSoft)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, 10)
    }

    private var editToolbar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                // Marquee tool — when on, drag the timeline to select / set the loop.
                Button { selectMode.toggle() } label: {
                    VStack(spacing: 2) {
                        Image(systemName: "selection.pin.in.out").font(.system(size: 15, weight: .semibold))
                        Text("Select").font(Theme.mono(8, .semibold))
                    }
                    .foregroundStyle(selectMode ? Theme.orange : Theme.etched)
                }
                Button { seq.selectionAllTracks.toggle() } label: {
                    Text(seq.selectionAllTracks ? "ALL" : "ONE")
                        .etchedLabel(9, weight: .bold)
                        .foregroundStyle(seq.selectionAllTracks ? Theme.orange : Theme.etchedSoft)
                }
                Divider().frame(height: 26)
                tool("Undo", "arrow.uturn.backward", enabled: seq.canUndo) { seq.undo() }
                tool("Cut", "scissors", enabled: seq.hasSelection) { model.editCut() }
                tool("Copy", "doc.on.doc", enabled: seq.hasSelection) { model.editCopy() }
                tool("Paste", "doc.on.clipboard", enabled: seq.hasClipboard) { model.editPaste() }
                tool("Erase", "eraser", enabled: seq.hasSelection) { model.editErase() }
                if seq.hasSelection {
                    tool("Deselect", "xmark.circle", enabled: true) { seq.clearSelection() }
                }
                Divider().frame(height: 26)
                tool("Loop In", "arrow.down.to.line", enabled: true) { seq.setLoopIn() }
                tool("Loop Out", "arrow.up.to.line", enabled: true) { seq.setLoopOut() }
                tool("Loop Sel", "repeat", enabled: seq.hasSelection) { seq.loopSelection() }
                if seq.hasLoopRegion {
                    tool("Clear Loop", "xmark", enabled: true) { seq.clearLoopRegion() }
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 5)
        }
        .background(Theme.rail)
    }

    private func tool(_ title: String, _ icon: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: icon).font(.system(size: 15, weight: .semibold))
                Text(title).font(Theme.mono(8, .semibold))
            }
            .foregroundStyle(enabled ? Theme.etched : Theme.etchedSoft.opacity(0.5))
        }
        .disabled(!enabled)
    }
}

// MARK: - Lane header (observes its Track)

private struct LaneHeaderView: View {
    @ObservedObject var track: Track
    let isSelected: Bool
    let onSelect: () -> Void
    var onEdit: () -> Void = {}

    var body: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2).fill(track.color).frame(width: 4, height: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(track.name).font(.caption.weight(.semibold)).foregroundStyle(Theme.etched).lineLimit(1)
                Text(track.instrumentName).etchedLabel(7, soft: true, weight: .medium).lineLimit(1)
            }
            Spacer(minLength: 0)
            if track.armed {
                Circle().fill(Color.red).frame(width: 6, height: 6)   // record-armed indicator
            }
        }
        .padding(.horizontal, 8)
        .frame(maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 6).fill(isSelected ? Theme.orange.opacity(0.12) : Color.white.opacity(0.25)))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(isSelected ? Theme.orange : Theme.gold.opacity(0.3), lineWidth: isSelected ? 1.5 : 1))
        .contentShape(Rectangle())
        .onTapGesture { isSelected ? onEdit() : onSelect() }   // tap selects; tap selected again = controls
    }
}

// MARK: - Ruler timeline (bars, loop band, playhead)

private struct RulerTimeline: View {
    @ObservedObject var seq: Sequencer
    let totalBeats: Int
    var selectMode = false
    var selectedTrackID: UUID?

    @State private var dragStartL: Double?   // captured edge beat at drag begin
    @State private var dragStartR: Double?
    private let selBlue = Color(red: 0.2, green: 0.55, blue: 0.95)

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let total = CGFloat(totalBeats)
            ZStack(alignment: .topLeading) {
                // Loop region band (orange)
                if seq.hasLoopRegion {
                    let x1 = CGFloat(seq.loopStartBeat) / total * w
                    let x2 = CGFloat(seq.loopEndBeat) / total * w
                    Rectangle().fill(Theme.orange.opacity(0.3))
                        .frame(width: max(2, x2 - x1), height: h).position(x: (x1 + x2) / 2, y: h / 2)
                }
                // Selection band (blue) with draggable edge handles — on the bar so
                // your finger isn't over the notes.
                if seq.hasSelection {
                    let x1 = CGFloat(seq.selStartBeat) / total * w
                    let x2 = CGFloat(seq.selEndBeat) / total * w
                    Rectangle().fill(selBlue.opacity(0.35))
                        .frame(width: max(2, x2 - x1), height: h).position(x: (x1 + x2) / 2, y: h / 2)
                    edgeHandle(x: x1, h: h, w: w, isLeft: true)
                    edgeHandle(x: x2, h: h, w: w, isLeft: false)
                }
                ForEach(0..<max(1, seq.loopBars), id: \.self) { bar in
                    let x = CGFloat(bar) / CGFloat(max(1, seq.loopBars)) * w
                    Text("\(bar + 1)").font(Theme.mono(9, .semibold)).foregroundStyle(Theme.etchedSoft)
                        .position(x: x + 8, y: h / 2)
                }
                let px = CGFloat(seq.positionBeats / max(0.001, seq.totalBeats)) * w
                Rectangle().fill(Theme.etched).frame(width: 1.5, height: h).position(x: px, y: h / 2)
            }
            .contentShape(Rectangle())
            // Select mode: drag the BAR to make a time selection (across the ALL/ONE scope).
            .conditionalDrag(selectMode) { start, cur in
                seq.setSelection(startBeat: Double(start / w) * Double(totalBeats),
                                 endBeat: Double(cur / w) * Double(totalBeats),
                                 trackID: selectedTrackID)
            }
            // Tap the bar to move the playhead.
            .gesture(
                SpatialTapGesture().onEnded { v in
                    seq.seek(toBeat: Double(v.location.x / w) * Double(totalBeats))
                }
            )
        }
    }

    /// A draggable selection edge: a line + grip with a wide touch zone. Works even
    /// when not in Select mode (high priority over the scroll view).
    private func edgeHandle(x: CGFloat, h: CGFloat, w: CGFloat, isLeft: Bool) -> some View {
        let g = seq.quantizeGrid.beats
        return ZStack {
            Rectangle().fill(selBlue).frame(width: 2, height: h)
            Capsule().fill(selBlue).frame(width: 7, height: 13).offset(y: -h / 2 + 7)   // grip knob
        }
        .frame(width: 26, height: h)                 // wide touch target
        .contentShape(Rectangle())
        .position(x: x, y: h / 2)
        .highPriorityGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { v in
                    let delta = Double(v.translation.width / w) * Double(totalBeats)
                    if isLeft {
                        if dragStartL == nil { dragStartL = seq.selStartBeat }
                        let nb = min((dragStartL ?? 0) + delta, seq.selEndBeat - g)   // keep ≥1 grid wide
                        seq.setSelection(startBeat: nb, endBeat: seq.selEndBeat, trackID: selectedTrackID)
                    } else {
                        if dragStartR == nil { dragStartR = seq.selEndBeat }
                        let nb = max((dragStartR ?? 0) + delta, seq.selStartBeat + g)
                        seq.setSelection(startBeat: seq.selStartBeat, endBeat: nb, trackID: selectedTrackID)
                    }
                }
                .onEnded { _ in dragStartL = nil; dragStartR = nil }
        )
    }
}

/// Attach a plain horizontal-drag gesture (high priority) only when `active`, so
/// in Select mode the timeline selects/sets-loop instead of scrolling.
private extension View {
    @ViewBuilder
    func conditionalDrag(_ active: Bool, _ onDrag: @escaping (CGFloat, CGFloat) -> Void) -> some View {
        if active {
            self.highPriorityGesture(
                DragGesture(minimumDistance: 3)
                    .onChanged { v in onDrag(v.startLocation.x, v.location.x) }
            )
        } else {
            self
        }
    }
}

// MARK: - Lane timeline (notes, selection, playhead) — observes its Track

private struct LaneTimelineView: View {
    @ObservedObject var track: Track
    @ObservedObject var seq: Sequencer
    let totalBeats: Int
    let loPitch: Int
    let hiPitch: Int
    let onSelect: () -> Void

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let loop = max(0.001, seq.totalBeats)
            let total = CGFloat(totalBeats)
            let rects = seq.noteRects(for: track.id)
            let span = CGFloat(hiPitch - loPitch)
            let mine = seq.selectionAllTracks || seq.selTrackID == track.id

            ZStack(alignment: .topLeading) {
                ForEach(0..<totalBeats, id: \.self) { b in
                    let x = CGFloat(b) / total * w
                    Rectangle().fill(Theme.gold.opacity(b % seq.beatsPerBar == 0 ? 0.3 : 0.12))
                        .frame(width: b % seq.beatsPerBar == 0 ? 1 : 0.5, height: h).position(x: x, y: h / 2)
                }
                if mine && seq.hasSelection {
                    let x1 = CGFloat(seq.selStartBeat) / total * w
                    let x2 = CGFloat(seq.selEndBeat) / total * w
                    Rectangle().fill(Color(red: 0.2, green: 0.55, blue: 0.95).opacity(0.28))
                        .frame(width: max(2, x2 - x1), height: h).position(x: (x1 + x2) / 2, y: h / 2)
                }
                ForEach(Array(rects.enumerated()), id: \.offset) { _, r in
                    let x = CGFloat(r.start / loop) * w
                    let nw = max(2, CGFloat((r.end - r.start) / loop) * w)
                    let y = h - CGFloat(Int(r.note) - loPitch) / span * h
                    RoundedRectangle(cornerRadius: 1).fill(track.color)
                        .frame(width: nw, height: 3).position(x: x + nw / 2, y: max(2, min(h - 2, y)))
                }
                let px = CGFloat(min(loop, max(0, seq.positionBeats)) / loop) * w
                Rectangle().fill(Theme.etched.opacity(0.8)).frame(width: 1.5, height: h).position(x: px, y: h / 2)
            }
            .contentShape(Rectangle())
            // Tap a lane to move the playhead and select that track. (Time selection
            // is made on the ruler bar above, so your finger doesn't cover the notes.)
            .gesture(
                SpatialTapGesture().onEnded { v in
                    seq.seek(toBeat: Double(v.location.x / w) * Double(totalBeats))
                    onSelect()
                }
            )
        }
    }
}
