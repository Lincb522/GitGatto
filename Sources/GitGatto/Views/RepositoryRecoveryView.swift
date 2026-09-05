import SwiftUI

struct RepositoryRecoveryView: View {
    @StateObject private var observation: RepositoryRecoveryObservation

    init(model: WorkspaceViewModel) {
        _observation = StateObject(wrappedValue: RepositoryRecoveryObservation(model: model))
    }

    private var model: WorkspaceViewModel { observation.model }
    @Environment(\.colorScheme) private var colorScheme
    @State private var pendingDeletion: BackupDeletionTarget?

    var body: some View {
        let palette = AppPalette(colorScheme)
        VStack(spacing: 0) {
            header(palette)
            Rectangle().fill(palette.divider).frame(height: 1)
            metrics(palette)
            Rectangle().fill(palette.divider).frame(height: 1)
            if !model.repositoryProtectionIncidents.isEmpty {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(model.repositoryProtectionIncidents) { incident in
                            protectionIncident(incident, palette: palette)
                        }
                    }
                }
                .frame(maxHeight: 180)
                Rectangle().fill(palette.divider).frame(height: 1)
            }

            if model.isLoadingRepositoryBackups, model.repositoryBackups.isEmpty {
                GattoLoadingState(text: L10n.text("recovery.loading"))
            } else if model.repositoryBackups.isEmpty {
                emptyState(palette)
            } else {
                HStack(spacing: 0) {
                    backupList(palette)
                        .frame(minWidth: 270, idealWidth: 320, maxWidth: 360)
                    Rectangle().fill(palette.divider).frame(width: 1)
                    backupDetail(palette)
                }
            }
        }
        .background(palette.background)
        .task {
            if model.repositoryBackups.isEmpty {
                await model.reloadRepositoryBackups()
            }
        }
        .alert(
            deletionTitle,
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: {
                    if !$0 {
                        pendingDeletion = nil
                    }
                }
            ),
            presenting: pendingDeletion
        ) { target in
            Button(L10n.text("action.cancel"), role: .cancel) {}
            Button(L10n.text("recovery.action.delete"), role: .destructive) {
                performDeletion(target)
            }
        } message: { target in
            Text(deletionMessage(target))
        }
    }

    private func protectionIncident(
        _ incident: RepositoryProtectionIncident,
        palette: AppPalette
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(gattoSymbol: "exclamationmark.triangle.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(palette.warning)
                .frame(width: 34, height: 34)
                .background(palette.warning.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.format("recovery.guard.incident.title", incident.repositoryName))
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(palette.ink)

                VStack(alignment: .leading, spacing: 3) {
                    if incident.kind == .repositoryUnavailable {
                        Text(L10n.text("recovery.guard.incident.repository_unavailable"))
                    }
                    if let assessment = incident.assessment {
                        if !assessment.deletedPaths.isEmpty {
                            Text(L10n.format(
                                "recovery.guard.incident.deleted",
                                assessment.deletedPaths.count
                            ))
                        }
                        if !assessment.lostChangedPaths.isEmpty {
                            Text(L10n.format(
                                "recovery.guard.incident.lost_changes",
                                assessment.lostChangedPaths.count
                            ))
                        }
                        if assessment.headChanged || assessment.branchChanged || assessment.indexChanged {
                            Text(L10n.text("recovery.guard.incident.git_state"))
                        }
                        if incident.exceedsConfiguredChangeLimit {
                            Text(L10n.format(
                                "recovery.guard.incident.threshold",
                                assessment.changedPathsSinceBaseline.count,
                                assessment.changedLineCountSinceBaseline
                            ))
                        }
                        let affectedPaths = Array(Set(
                            assessment.deletedPaths
                                + assessment.lostChangedPaths
                                + (incident.exceedsConfiguredChangeLimit
                                    ? assessment.changedPathsSinceBaseline
                                    : [])
                        )).sorted()
                        if !affectedPaths.isEmpty {
                            Text(affectedPaths.prefix(5).joined(separator: "  ·  "))
                                .font(.system(size: 10, design: .monospaced))
                                .lineLimit(2)
                        }
                    }
                    if let failureDescription = incident.failureDescription {
                        Text(failureDescription)
                            .font(.system(size: 10, design: .monospaced))
                            .lineLimit(3)
                            .textSelection(.enabled)
                    }
                }
                .font(.system(size: 11))
                .foregroundStyle(palette.mutedInk)

                HStack(spacing: 8) {
                    Button(L10n.text("recovery.guard.action.review")) {
                        model.reviewRepositoryProtectionIncident(incident)
                    }
                    .buttonStyle(PrimaryButtonStyle())

                    Button(L10n.text("recovery.guard.action.recovery")) {
                        model.openRepositoryProtectionIncident(incident)
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
            }

            Spacer(minLength: 0)

            Text(incident.detectedAt.formatted(date: .omitted, time: .shortened))
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(palette.subtleInk)

            Button {
                model.dismissRepositoryProtectionIncident(incident)
            } label: {
                Image(gattoSymbol: "xmark")
                    .font(.system(size: 10.5, weight: .semibold))
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .foregroundStyle(palette.subtleInk)
            .help(L10n.text("action.close"))
        }
        .padding(13)
        .background(palette.raisedSurface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(palette.warning.opacity(0.38), lineWidth: 1)
        }
        .padding(12)
        .background(palette.surface)
    }

    private func header(_ palette: AppPalette) -> some View {
        HStack(spacing: 12) {
            GattoIcon(symbol: "clock.badge.checkmark", size: 24)
                .foregroundStyle(palette.accent)
                .frame(width: 38, height: 38)
                .background(palette.accentSoft)
                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))

            Text(L10n.text("recovery.title"))
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(palette.ink)

            if model.appPreferences.repositoryBackupEnabled {
                GattoLabel(L10n.text("recovery.monitoring.active"), systemImage: "dot.radiowaves.left.and.right")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(palette.success)
            }

            Spacer(minLength: 12)

            Menu {
                Button {
                    model.revealRepositoryBackupStorage()
                } label: {
                    GattoLabel(L10n.text("recovery.action.reveal_root"), systemImage: "folder")
                }

                if let backup = model.selectedRepositoryBackup {
                    Button {
                        model.revealRepositoryBackup(backup)
                    } label: {
                        GattoLabel(L10n.text("recovery.action.reveal_backup"), systemImage: "archivebox")
                    }

                    Divider()

                    Button(role: .destructive) {
                        pendingDeletion = .repository(
                            path: backup.repositoryPath,
                            name: backup.repositoryName
                        )
                    } label: {
                        GattoLabel(
                            L10n.text("recovery.action.delete_repository"),
                            systemImage: "trash"
                        )
                    }
                }

                if !model.repositoryBackups.isEmpty {
                    Button(role: .destructive) {
                        pendingDeletion = .all
                    } label: {
                        GattoLabel(L10n.text("recovery.action.delete_all"), systemImage: "trash.slash")
                    }
                }
            } label: {
                GattoLabel(L10n.text("recovery.action.manage"), systemImage: "slider.horizontal.3")
            }
            .buttonStyle(SecondaryButtonStyle())

            Button {
                Task { await model.createManualRepositoryBackup() }
            } label: {
                if let activePath = model.activeRepositoryBackupPath,
                   let repositoryPath = model.snapshot?.rootURL.standardizedFileURL.path,
                   activePath == repositoryPath {
                    HStack(spacing: 7) {
                        ProgressView().controlSize(.small)
                        Text(L10n.text("recovery.creating"))
                    }
                } else {
                    GattoLabel(L10n.text("recovery.action.create"), systemImage: "plus")
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(model.snapshot == nil || model.activeRepositoryBackupPath != nil || model.isMigratingRepositoryBackupStorage)
        }
        .padding(.horizontal, 18)
        .frame(height: 64)
        .background(palette.surface)
    }

    private func metrics(_ palette: AppPalette) -> some View {
        HStack(spacing: 10) {
            metric(
                title: L10n.text("recovery.metric.repositories"),
                value: String(model.protectedRepositoryCount),
                icon: "folder.badge.plus",
                palette: palette
            )
            metric(
                title: L10n.text("recovery.metric.backups"),
                value: String(model.repositoryBackups.count),
                icon: "archivebox",
                palette: palette
            )
            metric(
                title: L10n.text("recovery.metric.storage"),
                value: ByteCountFormatter.string(
                    fromByteCount: model.repositoryBackupStorageBytes,
                    countStyle: .file
                ),
                icon: "externaldrive.fill",
                palette: palette
            )
            metric(
                title: L10n.text("recovery.metric.latest"),
                value: model.lastRepositoryBackupAt?.formatted(
                    date: .abbreviated,
                    time: .shortened
                ) ?? L10n.text("recovery.value.none"),
                icon: "clock.arrow.circlepath",
                palette: palette
            )
        }
        .padding(12)
        .background(palette.surface)
    }

    private func metric(
        title: String,
        value: String,
        icon: String,
        palette: AppPalette
    ) -> some View {
        HStack(spacing: 9) {
            Image(gattoSymbol: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(palette.accent)
                .frame(width: 28, height: 28)
                .background(palette.accentSoft)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(palette.subtleInk)
                Text(value)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(palette.ink)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 11)
        .frame(maxWidth: .infinity, minHeight: 48)
        .background(palette.raisedSurface)
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(palette.divider, lineWidth: 1)
        }
    }

    private func backupList(_ palette: AppPalette) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(L10n.text("recovery.list.title"))
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(palette.ink)
                Spacer()
                Button {
                    Task { await model.reloadRepositoryBackups() }
                } label: {
                    Image(gattoSymbol: "arrow.triangle.2.circlepath")
                        .font(.system(size: 11.5, weight: .semibold))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .foregroundStyle(palette.mutedInk)
                .disabled(model.isLoadingRepositoryBackups)
            }
            .padding(.horizontal, 14)
            .frame(height: 46)

            Rectangle().fill(palette.divider).frame(height: 1)

            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(model.repositoryBackups) { backup in
                        Button {
                            model.selectRepositoryBackup(backup)
                        } label: {
                            backupRow(
                                backup,
                                selected: model.selectedRepositoryBackup?.id == backup.id,
                                palette: palette
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(10)
            }
        }
        .background(palette.sidebar)
    }

    private func backupRow(
        _ backup: RepositoryBackup,
        selected: Bool,
        palette: AppPalette
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(backup.repositoryName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(palette.ink)
                    .lineLimit(1)
                Spacer(minLength: 4)
                slotBadge(backup, palette: palette)
                reasonBadge(backup.reason, palette: palette)
            }
            HStack(spacing: 7) {
                Text(backup.createdAt.formatted(date: .abbreviated, time: .shortened))
                Text(L10n.format("recovery.files.count", backup.changedFileCount))
                Spacer(minLength: 0)
            }
            .font(.system(size: 9.5, weight: .medium))
            .foregroundStyle(palette.subtleInk)
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(selected ? palette.accentSoft : palette.raisedSurface)
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(selected ? palette.accent : palette.divider, lineWidth: 1)
        }
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func backupDetail(_ palette: AppPalette) -> some View {
        if let backup = model.selectedRepositoryBackup {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top, spacing: 12) {
                        GattoIcon(symbol: "archivebox", size: 27)
                            .foregroundStyle(palette.accent)
                            .frame(width: 44, height: 44)
                            .background(palette.accentSoft)
                            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(backup.repositoryName)
                                .font(.system(size: 19, weight: .semibold))
                                .foregroundStyle(palette.ink)
                            Text(backup.createdAt.formatted(date: .long, time: .standard))
                                .font(.system(size: 10.5, weight: .medium))
                                .foregroundStyle(palette.subtleInk)
                        }
                        Spacer()
                        reasonBadge(backup.reason, palette: palette)
                    }

                    detailGrid(backup, palette: palette)

                    VStack(alignment: .leading, spacing: 7) {
                        Text(L10n.text("recovery.detail.source"))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(palette.ink)
                        Text(backup.repositoryPath)
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundStyle(palette.mutedInk)
                            .textSelection(.enabled)
                    }
                    .padding(13)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(palette.raisedSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(palette.divider, lineWidth: 1)
                    }

                    if backup.omittedFileCount > 0 {
                        GattoLabel(
                            L10n.format("recovery.detail.omitted", backup.omittedFileCount),
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(palette.warning)
                    }

                    if let error = model.repositoryProtectionError {
                        GattoLabel(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(palette.warning)
                            .textSelection(.enabled)
                    }

                    HStack(spacing: 10) {
                        Button(L10n.text("recovery.action.restore")) {
                            model.restoreRepositoryBackup(backup)
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(model.activeRepositoryBackupPath != nil || model.isMigratingRepositoryBackupStorage)

                        Button(L10n.text("recovery.action.delete"), role: .destructive) {
                            pendingDeletion = .backup(backup)
                        }
                        .buttonStyle(SecondaryButtonStyle())
                        .disabled(model.activeRepositoryBackupPath != nil || model.isMigratingRepositoryBackupStorage)

                        Button(L10n.text("recovery.action.reveal_backup")) {
                            model.revealRepositoryBackup(backup)
                        }
                        .buttonStyle(SecondaryButtonStyle())
                    }
                }
                .padding(20)
                .frame(maxWidth: 760, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .background(palette.background)
        } else {
            Text(L10n.text("recovery.detail.select"))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(palette.subtleInk)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func detailGrid(_ backup: RepositoryBackup, palette: AppPalette) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
            detailValue(
                L10n.text("recovery.detail.branch"),
                backup.branchName ?? L10n.text("recovery.value.detached"),
                palette: palette
            )
            detailValue(
                L10n.text("recovery.detail.files"),
                String(backup.changedFileCount),
                palette: palette
            )
            detailValue(
                L10n.text("recovery.detail.lines"),
                String(backup.changedLineCount),
                palette: palette
            )
            detailValue(
                L10n.text("recovery.detail.size"),
                ByteCountFormatter.string(fromByteCount: backup.storedByteCount, countStyle: .file),
                palette: palette
            )
            if let headSHA = backup.headSHA {
                detailValue(
                    L10n.text("recovery.detail.commit"),
                    String(headSHA.prefix(10)),
                    palette: palette
                )
            }
        }
    }

    private func detailValue(
        _ title: String,
        _ value: String,
        palette: AppPalette
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(palette.subtleInk)
            Text(value)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(palette.ink)
                .lineLimit(1)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.raisedSurface)
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(palette.divider, lineWidth: 1)
        }
    }

    private func reasonBadge(_ reason: RepositoryBackupReason, palette: AppPalette) -> some View {
        Text(L10n.text("recovery.reason.\(reason.rawValue)"))
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(reason == .majorChange ? palette.warning : palette.accent)
            .padding(.horizontal, 7)
            .frame(height: 20)
            .background(reason == .majorChange ? palette.warning.opacity(0.12) : palette.accentSoft)
            .clipShape(Capsule())
    }

    private func slotBadge(_ backup: RepositoryBackup, palette: AppPalette) -> some View {
        Text(L10n.text(backupSlotKey(backup)))
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(palette.ink)
            .padding(.horizontal, 7)
            .frame(height: 20)
            .background(palette.surface)
            .clipShape(Capsule())
            .overlay {
                Capsule().stroke(palette.divider, lineWidth: 1)
            }
    }

    private func backupSlotKey(_ backup: RepositoryBackup) -> String {
        return switch observation.slots[backup.id] {
        case 0: "recovery.slot.latest"
        case 1: "recovery.slot.previous"
        default: "recovery.slot.older"
        }
    }

    private var deletionTitle: String {
        switch pendingDeletion {
        case .backup:
            L10n.text("recovery.delete.confirm.title")
        case .repository:
            L10n.text("recovery.delete.repository_confirm.title")
        case .all:
            L10n.text("recovery.delete.all_confirm.title")
        case nil:
            L10n.text("recovery.delete.confirm.title")
        }
    }

    private func deletionMessage(_ target: BackupDeletionTarget) -> String {
        switch target {
        case let .backup(backup):
            L10n.format("recovery.delete.confirm.body", backup.repositoryName)
        case let .repository(_, name):
            L10n.format("recovery.delete.repository_confirm.body", name)
        case .all:
            L10n.text("recovery.delete.all_confirm.body")
        }
    }

    private func performDeletion(_ target: BackupDeletionTarget) {
        switch target {
        case let .backup(backup):
            Task { await model.deleteRepositoryBackup(backup) }
        case let .repository(path, _):
            Task { await model.deleteRepositoryBackups(for: path) }
        case .all:
            Task { await model.deleteAllRepositoryBackups() }
        }
    }

    private func emptyState(_ palette: AppPalette) -> some View {
        VStack(spacing: 12) {
            GattoIcon(symbol: "clock.badge.checkmark", size: 38)
                .foregroundStyle(palette.subtleInk)
            Text(L10n.text("recovery.empty.title"))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(palette.ink)
            if model.snapshot != nil {
                Button(L10n.text("recovery.action.create")) {
                    Task { await model.createManualRepositoryBackup() }
                }
                .buttonStyle(PrimaryButtonStyle())
            } else {
                Text(L10n.text("recovery.empty.open_repository"))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(palette.subtleInk)
            }
            if let error = model.repositoryProtectionError {
                Text(error)
                    .font(.system(size: 10.5))
                    .foregroundStyle(palette.warning)
                    .textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private enum BackupDeletionTarget: Identifiable {
    case backup(RepositoryBackup)
    case repository(path: String, name: String)
    case all

    var id: String {
        switch self {
        case let .backup(backup): "backup-\(backup.id.uuidString)"
        case let .repository(path, _): "repository-\(path)"
        case .all: "all"
        }
    }
}
