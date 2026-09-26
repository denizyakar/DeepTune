import SwiftUI

/// The instrument's headstock with one peg per string. Tapping a peg makes that
/// string the Auto tuner's target.
struct HeadstockView: View {
    let model: AutoTunerViewModel

    private struct PegAnchor: Identifiable {
        let noteIndex: Int
        let x: CGFloat
        let y: CGFloat

        var id: Int { noteIndex }
    }

    // Keeps the headstock zone clear and flexible for future image overlays.
    var body: some View {
        GeometryReader { proxy in
            let headstockCanvasSize = CGSize(
                width: proxy.size.width * 1.06,
                height: proxy.size.height * 1.56
            )

            ZStack {
                ZStack(alignment: .topLeading) {
                    Image(model.currentInstrument.type.headstockImageName)
                        .resizable()
                        .scaledToFill()
                        .frame(
                            width: headstockCanvasSize.width,
                            height: headstockCanvasSize.height,
                            alignment: .bottom
                        )
                        .clipped()
                        .allowsHitTesting(false)

                    pegLayout(in: headstockCanvasSize)
                        .frame(
                            width: headstockCanvasSize.width,
                            height: headstockCanvasSize.height,
                            alignment: .topLeading
                        )
                }
                .frame(
                    width: headstockCanvasSize.width,
                    height: headstockCanvasSize.height,
                    alignment: .bottom
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .clipped()
        }
    }

    @ViewBuilder
    private func pegLayout(in canvasSize: CGSize) -> some View {
        let notes = model.currentTuning.notes
        let anchors = pegAnchors(
            for: model.currentInstrument.type,
            noteCount: notes.count
        )

        if anchors.isEmpty {
            HStack(spacing: 10) {
                ForEach(notes) { note in
                    peg(for: note)
                }
            }
        } else {
            ZStack {
                ForEach(anchors) { anchor in
                    if anchor.noteIndex < notes.count {
                        peg(for: notes[anchor.noteIndex])
                            .position(
                                x: canvasSize.width * anchor.x,
                                y: canvasSize.height * anchor.y
                            )
                    }
                }
            }
        }
    }

    private func pegAnchors(for type: InstrumentType, noteCount: Int) -> [PegAnchor] {
        switch type {
        case .guitar6:
            return [
                PegAnchor(noteIndex: 0, x: 0.08, y: 0.465),
                PegAnchor(noteIndex: 1, x: 0.12, y: 0.388),
                PegAnchor(noteIndex: 2, x: 0.165, y: 0.31),
                PegAnchor(noteIndex: 3, x: 0.21, y: 0.235),
                PegAnchor(noteIndex: 4, x: 0.255, y: 0.16),
                PegAnchor(noteIndex: 5, x: 0.30, y: 0.085)
            ]
        case .guitar7, .guitar8:
            return [
                PegAnchor(noteIndex: 0, x: 0.08, y: 0.465),
                PegAnchor(noteIndex: 1, x: 0.12, y: 0.388),
                PegAnchor(noteIndex: 2, x: 0.165, y: 0.31),
                PegAnchor(noteIndex: 3, x: 0.21, y: 0.235),
                PegAnchor(noteIndex: 4, x: 0.26, y: 0.23),
                PegAnchor(noteIndex: 5, x: 0.28, y: 0.15),
                PegAnchor(noteIndex: 6, x: 0.30, y: 0.08),
                PegAnchor(noteIndex: 7, x: 0.32, y: 0.05)
            ].prefix(noteCount).map { $0 }
        case .bass:
            return [
                PegAnchor(noteIndex: 0, x: 0.08, y: 0.465),
                PegAnchor(noteIndex: 1, x: 0.135, y: 0.34),
                PegAnchor(noteIndex: 2, x: 0.19, y: 0.22),
                PegAnchor(noteIndex: 3, x: 0.25, y: 0.10)
            ]
        case .ukulele:
            return [
                PegAnchor(noteIndex: 0, x: 0.065, y: 0.52),
                PegAnchor(noteIndex: 1, x: 0.065, y: 0.32),
                PegAnchor(noteIndex: 2, x: 0.89, y: 0.32),
                PegAnchor(noteIndex: 3, x: 0.89, y: 0.52)
            ]
        }
    }

    private func peg(for note: Note) -> some View {
        PegButton(
            note: note,
            isActive: model.targetNote == note,
            isCompleted: model.isNoteCompleted(note)
        )
        .scaleEffect(pegScale(for: model.currentInstrument.type))
        .onTapGesture {
            model.setTargetNote(note)
        }
    }

    private func pegScale(for type: InstrumentType) -> CGFloat {
        switch type {
        case .guitar7, .guitar8:
            return 0.80
        case .guitar6:
            return 0.86
        case .bass:
            return 0.88
        case .ukulele:
            return 0.92
        }
    }
}

struct PegButton: View {
    @Environment(\.colorScheme) private var colorScheme

    var note: Note
    var isActive: Bool
    var isCompleted: Bool = false

    var body: some View {
        Text(note.name)
            .font(.headline.weight(.bold))
            .frame(width: 48, height: 48)
            .background(
                Circle()
                    .fill(isActive ? AppTheme.accent : AppTheme.surfaceElevated)
                    .overlay(
                        Circle()
                            .stroke(AppTheme.stroke.opacity(isActive ? (colorScheme == .dark ? 0.40 : 0.40) : (colorScheme == .dark ? 0.85 : 0.85)), lineWidth: 1)
                    )
                    .shadow(color: (colorScheme == .dark ? AppTheme.accent.opacity(isActive ? 0.32 : 0.18) : Color.black.opacity(isActive ? 0.20 : 0.08)), radius: isActive ? 8 : 5, x: 0, y: 3)
            )
            .foregroundColor(isActive ? .white : AppTheme.textPrimary)
            .animation(.spring(response: 0.24, dampingFraction: 0.84), value: isActive)
            .overlay(alignment: .topTrailing) {
                if isCompleted {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(AppTheme.success)
                        .background(Circle().fill(AppTheme.surfacePrimary))
                        .offset(x: 4, y: -4)
                }
            }
    }
}
