import Foundation
import Testing
@testable import MemLensCore

/// Smoke tests against the live system. Assertions are deliberately loose.
@Suite struct LiveSystemReaderTests {
    let reader = LiveSystemReader()
    let me = getpid()

    @Test func listsOwnPid() {
        #expect(reader.listPids().contains(me))
    }

    @Test func readsOwnExecutablePath() throws {
        let path = try #require(reader.executablePath(pid: me))
        #expect(path.hasPrefix("/"))
    }

    @Test func readsOwnFootprint() throws {
        let bytes = try #require(reader.footprintBytes(pid: me))
        #expect(bytes > 0)
    }

    @Test func readsOwnCommandLine() throws {
        let args = try #require(reader.commandLine(pid: me))
        #expect(!args.isEmpty)
    }

    @Test func unreadablePidReturnsNil() {
        #expect(reader.footprintBytes(pid: 0x7FFF_FFF0) == nil)
        #expect(reader.executablePath(pid: 0x7FFF_FFF0) == nil)
        #expect(reader.commandLine(pid: 0x7FFF_FFF0) == nil)
        #expect(reader.filePaths(pid: 0x7FFF_FFF0).isEmpty)
    }

    @Test func pressureLevelIsReadable() {
        #expect(PressureLevel.allCases.contains(reader.pressureLevel()))
    }

    @Test func seesOpenFileDescriptor() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("memlens-fd-\(UUID().uuidString).txt")
        try Data("x".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let name = url.lastPathComponent
        #expect(reader.filePaths(pid: me).contains { $0.hasSuffix(name) })
    }

    @Test func seesMemoryMappedFileAfterFdIsClosed() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("memlens-map-\(UUID().uuidString).bin")
        try Data(count: 1 << 16).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let fd = open(url.path, O_RDONLY)
        try #require(fd >= 0)
        let length = 1 << 16
        let mapping = mmap(nil, length, PROT_READ, MAP_PRIVATE, fd, 0)
        close(fd)
        defer { munmap(mapping, length) }
        let name = url.lastPathComponent
        #expect(reader.filePaths(pid: me).contains { $0.hasSuffix(name) })
    }

    @Test func runningAppsInvariantsHold() {
        // Headless runs may see zero GUI apps; the invariants must hold either way.
        let apps = reader.runningApps()
        #expect(apps.allSatisfy { !$0.bundlePath.isEmpty && $0.pid > 0 })
        #expect(apps.filter(\.isFrontmost).count <= 1)
    }
}
