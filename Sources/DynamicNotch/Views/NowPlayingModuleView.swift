import SwiftUI

struct NowPlayingModuleView: View {
    @ObservedObject var service: NowPlayingService
    @ObservedObject var recorder: ScreenRecorderService = .shared
    @ObservedObject var stateModel: NotchStateModel

    private func accentColor(for source: MediaSourceType?) -> Color {
        switch source {
        case .youtube:
            return Color(red: 1.0, green: 0.23, blue: 0.23)
        case .spotify:
            return Color(red: 0.12, green: 0.84, blue: 0.38)
        case .music:
            return Color(red: 0.98, green: 0.34, blue: 0.48)
        case .whatsapp:
            return Color(red: 0.15, green: 0.83, blue: 0.44)
        case .audio:
            return Color.orange
        case .web, .none:
            return Color.white.opacity(0.65)
        }
    }

    private func iconName(for source: MediaSourceType?) -> String {
        switch source {
        case .youtube:
            return "play.rectangle.fill"
        case .spotify:
            return "waveform"
        case .music:
            return "music.note"
        case .whatsapp:
            return "phone.bubble.left.fill"
        case .audio:
            return "speaker.wave.2.fill"
        case .web, .none:
            return "play.circle"
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            // LADO IZQUIERDO: Reproductor de Audio / Video / Música
            leftMediaSection
                .frame(maxWidth: .infinity, alignment: .leading)

            // LADO DERECHO: Botón de Grabación de Pantalla completa con micrófono y audio
            rightRecordingSection
                .frame(width: 130, alignment: .trailing)
        }
    }

    // MARK: - Left Media Section
    @ViewBuilder
    private var leftMediaSection: some View {
        if let active = service.activeSource {
            HStack(spacing: 8) {
                // Mini Artwork / Icon
                ZStack(alignment: .bottomTrailing) {
                    if let art = service.artworkImage {
                        Image(nsImage: art)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 36, height: 36)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    } else {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.white.opacity(0.08))
                            .frame(width: 36, height: 36)
                            .overlay(
                                Image(systemName: iconName(for: active))
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(accentColor(for: active))
                            )
                    }

                    Circle()
                        .fill(accentColor(for: active))
                        .frame(width: 7, height: 7)
                        .overlay(Circle().stroke(Color.black, lineWidth: 1))
                        .offset(x: 1, y: 1)
                }

                // Title + Subtitle
                VStack(alignment: .leading, spacing: 2) {
                    Text(service.trackTitle)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Text(service.artistName.isEmpty ? active.rawValue : service.artistName)
                        .font(.system(size: 9.5, weight: .regular, design: .rounded))
                        .foregroundColor(.white.opacity(0.52))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Play / Pause Mini Button
                Button(action: { service.togglePlayPause() }) {
                    Image(systemName: service.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 26, height: 26)
                        .background(Color.white.opacity(0.14))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
        } else {
            HStack(spacing: 8) {
                Circle()
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 32, height: 32)
                    .overlay(
                        Image(systemName: "waveform")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white.opacity(0.45))
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text("Cualquier app")
                        .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.8))
                    Text("Música, video o audio")
                        .font(.system(size: 9, weight: .regular, design: .rounded))
                        .foregroundColor(.white.opacity(0.42))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: - Right Recording Section
    private var rightRecordingSection: some View {
        Button(action: {
            recorder.toggleRecording { msg, isErr in
                stateModel.showBanner(msg, isError: isErr)
            }
        }) {
            HStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(recorder.isRecording ? Color.red : Color.red.opacity(0.2))
                        .frame(width: 18, height: 18)

                    if recorder.isRecording {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.white)
                            .frame(width: 7, height: 7)
                    } else {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 8, height: 8)
                    }
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(recorder.isRecording ? "Detener" : "Grabar")
                        .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                        .foregroundColor(recorder.isRecording ? .red : .white)

                    Text(recorder.isRecording ? recorder.formattedDuration : "Pantalla + Mic")
                        .font(.system(size: 8.5, weight: .regular, design: .rounded))
                        .foregroundColor(recorder.isRecording ? Color.white.opacity(0.85) : Color.white.opacity(0.45))
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(
                recorder.isRecording
                    ? Color.red.opacity(0.18)
                    : Color.white.opacity(0.08)
            )
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(recorder.isRecording ? Color.red.opacity(0.6) : Color.white.opacity(0.12), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .help(recorder.isRecording ? "Detener y guardar grabación en ~/Movies" : "Iniciar grabación de pantalla completa con audio")
    }
}
