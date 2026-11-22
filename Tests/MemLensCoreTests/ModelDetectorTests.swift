import Foundation
import Testing
@testable import MemLensCore

private final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current = Date(timeIntervalSince1970: 1_000_000)
    var now: Date { lock.withLock { current } }
    func advance(_ seconds: TimeInterval) { lock.withLock { current = current.addingTimeInterval(seconds) } }
}

@Suite struct ModelDetectorTests {
    static let fluxFile =
        "/Users/me/.cache/huggingface/hub/models--black-forest-labs--FLUX.1-schnell/snapshots/abc123/"
        + "transformer/diffusion_pytorch_model.safetensors"

    @Test func extractsModelNameFromHuggingFaceCachePath() {
        #expect(ModelDetector.modelName(fromHFCachePath: Self.fluxFile) == "FLUX.1-schnell")
    }

    @Test func ignoresPathsOutsideTheModelCache() {
        #expect(ModelDetector.modelName(fromHFCachePath: "/Users/me/.cache/huggingface/hub/version.txt") == nil)
        #expect(ModelDetector.modelName(fromHFCachePath: "/Users/me/models--x--y/notes.txt") == nil)
    }

    @Test func detectsFluxFromOpenFile() {
        let fake = FakeSystemReader()
        fake.add(pid: 7, path: "/usr/bin/python3", footprint: 11 * GB,
                 args: ["python3", "gen.py"], files: ["/dev/null", Self.fluxFile])
        let detector = ModelDetector(reader: fake)
        #expect(detector.detect(pid: 7) == "FLUX.1-schnell")
    }

    @Test func detectsModelFromCommandLineFlag() {
        #expect(ModelDetector.modelName(fromArguments: ["python", "run.py", "--model", "black-forest-labs/FLUX.1-dev"]) == "FLUX.1-dev")
        #expect(ModelDetector.modelName(fromArguments: ["python", "--model=mistralai/Mistral-7B"]) == "Mistral-7B")
    }

    /// mflux closes the weight files after loading, so the cache-path rule only
    /// works for the first seconds; its `--model` takes a short alias instead.
    @Test func detectsMfluxModelAlias() {
        let mflux = "/Users/me/proj/venv/bin/mflux-generate"
        #expect(ModelDetector.modelName(fromArguments: ["Python", mflux, "--model", "schnell", "--quantize", "4"])
            == "FLUX.1-schnell")
        #expect(ModelDetector.modelName(fromArguments: ["Python", mflux, "-m", "dev"]) == "FLUX.1-dev")
        #expect(ModelDetector.modelName(fromArguments: ["Python", mflux, "--model=schnell"]) == "FLUX.1-schnell")
        // Other mflux aliases are the user's own model name: shown as given, not guessed.
        #expect(ModelDetector.modelName(fromArguments: ["Python", mflux, "--model", "z-image-turbo"]) == "z-image-turbo")
        // Local checkpoint paths still never count as a name.
        #expect(ModelDetector.modelName(fromArguments: ["Python", mflux, "--model", "/models/ckpt"]) == nil)
    }

    @Test func shortAliasNeedsMflux() {
        #expect(ModelDetector.modelName(fromArguments: ["python", "run.py", "--model", "schnell"]) == nil)
        // An mflux-named data file is not the mflux executable.
        #expect(ModelDetector.modelName(fromArguments: ["python", "run.py", "mflux_notes.txt", "--model", "schnell"]) == nil)
    }

    @Test func mfluxEdgeCases() {
        let mflux = "/venv/bin/mflux-generate"
        #expect(ModelDetector.modelName(fromArguments: ["Python", mflux, "--model=dev"]) == "FLUX.1-dev")
        #expect(ModelDetector.modelName(fromArguments: ["Python", mflux, "--model", "krea-dev"]) == "FLUX.1-Krea-dev")
        #expect(ModelDetector.modelName(fromArguments: ["Python", mflux, "--prompt", "x"]) == nil)
        #expect(ModelDetector.modelName(fromArguments: ["Python", mflux, "--model"]) == nil)
        #expect(ModelDetector.modelName(fromArguments: ["Python", mflux, "--model", "--steps"]) == nil)
    }

    @Test func mfluxRuntimeLabelWithoutKnownModel() {
        #expect(ModelDetector.runtimeLabel(fromArguments: ["Python", "/venv/bin/mflux-generate"]) == "mflux")
    }

    @Test func doesNotTreatPlainPathsAsModels() {
        #expect(ModelDetector.modelName(fromArguments: ["python", "scripts/run.py"]) == nil)
        #expect(ModelDetector.modelName(fromArguments: ["python", "--model", "./local/dir"]) == nil)
        #expect(ModelDetector.modelName(fromArguments: ["python", "--model", "/abs/path/model"]) == nil)
    }

    @Test func fallsBackToRuntimeKeyword() {
        #expect(ModelDetector.runtimeLabel(fromArguments: ["python", "/opt/ComfyUI/main.py"]) == "ComfyUI")
        #expect(ModelDetector.runtimeLabel(fromArguments: ["python", "-m", "mlx_lm.server"]) == "MLX")
        #expect(ModelDetector.runtimeLabel(fromArguments: ["python", "llama_cpp_server.py"]) == "llama")
        #expect(ModelDetector.runtimeLabel(fromArguments: ["python", "run_diffusers.py"]) == "diffusers")
        #expect(ModelDetector.runtimeLabel(fromArguments: ["python", "train_torch.py"]) == "PyTorch")
        #expect(ModelDetector.runtimeLabel(fromArguments: ["python", "hello.py"]) == nil)
    }

    @Test func neverGuessesWhenNothingMatches() {
        let fake = FakeSystemReader()
        fake.add(pid: 8, path: "/usr/bin/python3", footprint: GB, args: ["python3", "hello.py"], files: ["/tmp/a.txt"])
        #expect(ModelDetector(reader: fake).detect(pid: 8) == nil)
    }

    @Test func modelNameBeatsRuntimeKeyword() {
        let fake = FakeSystemReader()
        fake.add(pid: 9, path: "/usr/bin/python3", footprint: GB,
                 args: ["python3", "run_diffusers.py"], files: [Self.fluxFile])
        #expect(ModelDetector(reader: fake).detect(pid: 9) == "FLUX.1-schnell")
    }

    @Test func positiveResultIsCachedPerPid() {
        let fake = FakeSystemReader()
        fake.add(pid: 7, path: "/usr/bin/python3", footprint: GB, args: ["python3"], files: [Self.fluxFile])
        let detector = ModelDetector(reader: fake)
        _ = detector.detect(pid: 7)
        _ = detector.detect(pid: 7)
        #expect(fake.filePathsCallCount(pid: 7) == 1)
    }

    @Test func negativeResultIsRecheckedAfterInterval() {
        let clock = TestClock()
        let fake = FakeSystemReader()
        fake.add(pid: 7, path: "/usr/bin/python3", footprint: GB, args: ["python3", "gen.py"], files: [])
        let detector = ModelDetector(reader: fake, negativeRecheckInterval: 10, now: { clock.now })

        #expect(detector.detect(pid: 7) == nil)
        clock.advance(5)
        #expect(detector.detect(pid: 7) == nil)
        #expect(fake.filePathsCallCount(pid: 7) == 1)   // still cached

        fake.setFiles(pid: 7, [Self.fluxFile])           // model finished loading
        clock.advance(6)
        #expect(detector.detect(pid: 7) == "FLUX.1-schnell")
        #expect(fake.filePathsCallCount(pid: 7) == 2)
    }

    @Test func runtimeLabelIsUpgradedToModelNameOnceLoaded() {
        let clock = TestClock()
        let fake = FakeSystemReader()
        fake.add(pid: 7, path: "/usr/bin/python3", footprint: GB, args: ["python", "/opt/ComfyUI/main.py"], files: [])
        let detector = ModelDetector(reader: fake, negativeRecheckInterval: 10, now: { clock.now })

        #expect(detector.detect(pid: 7) == "ComfyUI")
        fake.setFiles(pid: 7, [Self.fluxFile])
        clock.advance(5)
        #expect(detector.detect(pid: 7) == "ComfyUI")
        #expect(fake.filePathsCallCount(pid: 7) == 1)   // label cached within interval

        clock.advance(6)
        #expect(detector.detect(pid: 7) == "FLUX.1-schnell")
        #expect(fake.filePathsCallCount(pid: 7) == 2)

        clock.advance(11)
        #expect(detector.detect(pid: 7) == "FLUX.1-schnell")
        #expect(fake.filePathsCallCount(pid: 7) == 2)   // model hit kept
    }

    @Test func pruneForgetsDeadPids() {
        let fake = FakeSystemReader()
        fake.add(pid: 7, path: "/usr/bin/python3", footprint: GB, args: ["python3"], files: [Self.fluxFile])
        let detector = ModelDetector(reader: fake)
        _ = detector.detect(pid: 7)
        detector.prune(livePids: [])
        _ = detector.detect(pid: 7)
        #expect(fake.filePathsCallCount(pid: 7) == 2)
    }
}
