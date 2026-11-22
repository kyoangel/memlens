import Testing
@testable import MemLensCore

@Suite struct GrouperTests {
    static let chrome = "/Applications/Google Chrome.app"
    static let helper =
        chrome + "/Contents/Frameworks/Google Chrome Framework.framework/Versions/1/Helpers/"
        + "Google Chrome Helper (Renderer).app/Contents/MacOS/Google Chrome Helper (Renderer)"

    @Test func mergesTwentyChromeHelpersIntoOneApp() {
        var processes = [RawProcess(pid: 100, path: Self.chrome + "/Contents/MacOS/Google Chrome", footprint: 400 * MB)]
        for i in 0..<20 {
            processes.append(RawProcess(pid: Int32(200 + i), path: Self.helper, footprint: 150 * MB))
        }

        let groups = Grouper.group(processes)

        #expect(groups.count == 1)
        let group = groups[0]
        #expect(group.name == "Google Chrome")
        #expect(group.kind == .app)
        #expect(group.bundlePath == Self.chrome)
        #expect(group.id == Self.chrome)  // MenuContentView loads candidate icons from this id
        #expect(group.pids.count == 21)
        #expect(group.footprint == 400 * MB + 20 * 150 * MB)
    }

    @Test func sortsLargestFirst() {
        let groups = Grouper.group([
            RawProcess(pid: 1, path: "/Applications/Small.app/Contents/MacOS/Small", footprint: 100 * MB),
            RawProcess(pid: 2, path: "/Applications/Big.app/Contents/MacOS/Big", footprint: 2 * GB),
        ])
        #expect(groups.map(\.name) == ["Big", "Small"])
    }

    @Test func eachPythonProcessIsItsOwnGroup() {
        let groups = Grouper.group([
            RawProcess(pid: 50, path: "/Users/me/proj/.venv/bin/python3.12", footprint: 11 * GB),
            RawProcess(pid: 51, path: "/opt/homebrew/bin/python3", footprint: 300 * MB),
        ])
        #expect(groups.count == 2)
        #expect(groups.allSatisfy { $0.kind == .python && $0.name == "Python" })
        #expect(Set(groups.map(\.id)) == ["pid:50", "pid:51"])
    }

    @Test func homebrewPythonAppBundleIsStillPython() {
        let path = "/opt/homebrew/Cellar/python@3.12/3.12.4/Frameworks/Python.framework/Versions/3.12/"
            + "Resources/Python.app/Contents/MacOS/Python"
        let groups = Grouper.group([RawProcess(pid: 60, path: path, footprint: 1 * GB)])
        #expect(groups[0].kind == .python)
    }

    @Test func displayNameShowsDetectedModelOnly() {
        var group = ProcessGroup(id: "pid:1", kind: .python, name: "Python", pids: [1], footprint: GB)
        #expect(group.displayName == "Python")
        group.model = "FLUX.1-schnell"
        #expect(group.displayName == "Python · FLUX.1-schnell")
    }

    @Test func systemDaemonsArePooled() {
        let groups = Grouper.group([
            RawProcess(pid: 1, path: "/usr/libexec/trustd", footprint: 20 * MB),
            RawProcess(pid: 2, path: "/System/Library/PrivateFrameworks/Foo.framework/foo", footprint: 30 * MB),
        ])
        #expect(groups.count == 1)
        #expect(groups[0].kind == .system)
        #expect(groups[0].name == "Other (system)")
        #expect(groups[0].footprint == 50 * MB)
    }

    @Test func nonBundledProcessesMergeByExecutableName() {
        let groups = Grouper.group([
            RawProcess(pid: 1, path: "/opt/homebrew/bin/node", footprint: 200 * MB),
            RawProcess(pid: 2, path: "/opt/homebrew/bin/node", footprint: 300 * MB),
        ])
        #expect(groups.count == 1)
        #expect(groups[0].name == "node")
        #expect(groups[0].footprint == 500 * MB)
    }

    @Test func usrLocalBinariesAreNotSystemProcesses() {
        let groups = Grouper.group([
            RawProcess(pid: 1, path: "/usr/local/bin/llama-server", footprint: 3 * GB),
            RawProcess(pid: 2, path: "/usr/libexec/trustd", footprint: 20 * MB),
        ])
        let llama = groups.first { $0.id == "proc:llama-server" }
        #expect(llama?.kind == .process)
        #expect(llama?.name == "llama-server")
        #expect(llama?.pids == [1])
        #expect(groups.first { $0.kind == .system }?.pids == [2])
    }

    /// Claude Code installs to `~/.local/share/claude/versions/<version>`; the
    /// resolved executable name is just the version, so name it by its tool dir.
    @Test func versionNamedExecutableTakesToolDirectoryName() {
        let groups = Grouper.group([
            RawProcess(pid: 1, path: "/Users/me/.local/share/claude/versions/2.1.322", footprint: 400 * MB),
            RawProcess(pid: 2, path: "/Users/me/.local/share/claude/versions/2.1.322", footprint: 300 * MB),
            RawProcess(pid: 3, path: "/Users/me/.local/share/claude/versions/2.1.321", footprint: 100 * MB),
        ])
        #expect(groups.count == 1)
        #expect(groups[0].kind == .process)
        #expect(groups[0].name == "Claude Code")
        #expect(groups[0].id == "proc:claude")
        #expect(groups[0].footprint == 800 * MB)
    }

    @Test func versionLikeNameWithoutToolDirectoryIsKept() {
        let groups = Grouper.group([RawProcess(pid: 1, path: "/1.0/v2.3", footprint: MB)])
        #expect(groups[0].name == "v2.3")
    }

    @Test func versionLikeNameNeverTakesGenericDirectoryName() {
        let groups = Grouper.group([
            RawProcess(pid: 1, path: "/opt/homebrew/bin/1.2", footprint: MB),
            RawProcess(pid: 2, path: "/Users/me/2.1.3", footprint: MB),
        ])
        #expect(Set(groups.map(\.name)) == ["1.2", "2.1.3"])
    }

    @Test func systemAppsKeepTheirOwnGroup() {
        let groups = Grouper.group([
            RawProcess(pid: 1, path: "/System/Applications/Safari.app/Contents/MacOS/Safari", footprint: GB),
        ])
        #expect(groups[0].kind == .app)
        #expect(groups[0].name == "Safari")
    }
}

@Suite struct GroupSymbolTests {
    @Test func appsUseTheirBundleIconSoHaveNoSymbol() {
        let group = ProcessGroup(id: "/Applications/LINE.app", kind: .app, name: "LINE",
                                 bundlePath: "/Applications/LINE.app", pids: [1], footprint: GB)
        #expect(group.symbolName == nil)
    }

    @Test func nonAppKindsGetDistinctSymbols() {
        func symbol(_ kind: ProcessGroup.Kind) -> String? {
            ProcessGroup(id: "x", kind: kind, name: "x", pids: [1], footprint: MB).symbolName
        }
        #expect(symbol(.process) == "terminal")
        #expect(symbol(.python) == "cpu")
        #expect(symbol(.system) == "gearshape")
    }
}
