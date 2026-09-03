let meta = #{
    name: "screen-send-proof",
    description: "Prove screen send on connected Flutter devices via native_screen_test and the example harness",
    when_to_use: "Screen send receipts, native_screen_test, flutter-skill share proof on windows linux android chrome macos ios",
    phases: [
        #{ title: "Discover", detail: "list flutter devices" },
        #{ title: "Prove", detail: "one agent per connected platform" },
        #{ title: "Synthesize", detail: "receipt matrix" },
    ],
};

let known = ["windows", "linux", "android", "chrome", "macos", "ios"];
let wanted = known;
if args != () && args.platforms != () {
    wanted = [];
    for p in args.platforms {
        wanted.push(p);
    }
}

phase("Discover");
let discover_prompt = "";
discover_prompt += "Prove screen send setup for flutter_ai_communications. ";
discover_prompt += "Working directory is the repo root. Run `flutter devices` via the shell. ";
discover_prompt += "Read `.agents/workflows/screen-send-orchestration.md` with read_file. ";
discover_prompt += "Return a markdown list of connected device ids and their platform names. ";
discover_prompt += "Use only these platform names: windows, linux, android, chrome, macos, ios. ";
discover_prompt += "If flutter devices fails, say so and list no devices. ";
discover_prompt += "Do not start tests in this step.";
let discovered = agent(discover_prompt, #{
    label: "discover-devices",
    capability_mode: "execute",
});

fn text_has(hay, needle) {
    let text = hay;
    if type_of(text) != "string" {
        text = json_encode(text);
    }
    let nlen = needle.len();
    let tlen = text.len();
    if nlen == 0 || tlen < nlen {
        return false;
    }
    let i = 0;
    while i + nlen <= tlen {
        if text.sub_string(i, nlen) == needle {
            return true;
        }
        i += 1;
    }
    false
}

let available = [];
if discovered != () && discovered.success && discovered.output != () {
    for name in known {
        let keep = false;
        for w in wanted {
            if w == name { keep = true; }
        }
        if keep && text_has(discovered.output, name) {
            available.push(name);
        }
    }
}
log("platforms to prove: " + json_encode(available));

if available.len() == 0 {
    complete(#{
        summary: "No matching Flutter devices. Connect a head and re-run.",
        platforms: wanted,
        receipts: [],
    });
}

phase("Prove");
let jobs = [];
for name in available {
    let prompt = "";
    prompt += "You are collecting a native screen send receipt for platform `";
    prompt += name;
    prompt += "` in flutter_ai_communications.\n";
    prompt += "Read and follow `.agents/workflows/screen-send-orchestration.md` and `docs/spec-screen-v1.md`.\n";
    prompt += "From `example/`, run:\n";
    prompt += "`flutter test integration_test/native_screen_test.dart -d ";
    prompt += name;
    prompt += "`\n";
    prompt += "Use a timeout of at least 8 minutes. Capture the full output.\n";
    prompt += "Parse `NATIVE_ORCHESTRATION_RECEIPT` JSON if printed.\n";
    prompt += "Treat `skipped=none` (empty catalog) and `skipped=os-picker` as receipts, not passes.\n";
    prompt += "A pass is only `skipped=false` with a local Video surface and twenty cycles.\n";
    prompt += "Loopback identity is not native proof. Do not wrap the platform in LoopbackCommunicationsPlatform.\n";
    prompt += "If the catalog is system-picker only, do not hang on the OS picker in the unattended test.\n";
    prompt += "If flutter-skill MCP is connected and the platform is android, chrome, or ios, also launch `example/` ";
    prompt += "and drive keys lobby-enter, lobby-join, screen-share, screen-loopback, screen-stop. ";
    prompt += "Wait for a human on the OS picker. Screenshot catalog, loopback, and stop.\n";
    prompt += "If flutter-skill is not connected, report that and keep the automated receipt.\n";
    prompt += "Return a short markdown report: platform, device id, skipped value, pass/fail, receipt path, evidence quotes.";
    jobs.push(#{
        prompt: prompt,
        label: "prove:" + name,
        capability_mode: "execute",
    });
}
let results = parallel(jobs);

phase("Synthesize");
let reports = [];
let i = 0;
for r in results {
    let platform_name = available[i];
    i += 1;
    if r == () || !r.success || r.output == () {
        reports.push("- " + platform_name + ": unverified (agent failed)");
    } else {
        let body = r.output;
        if type_of(body) != "string" {
            body = json_encode(body);
        }
        reports.push("## " + platform_name + "\n\n" + body);
    }
}

let markdown = "# Screen send proof\n\n";
markdown += "Automated seam: `example/integration_test/native_screen_test.dart`.\n";
markdown += "Job: `.agents/workflows/screen-send-orchestration.md`.\n";
markdown += "Close GitHub issue #44 only with skipped=false receipts for shipped graphs.\n\n";
for block in reports {
    markdown += block;
    markdown += "\n\n";
}
let path = write_scratch_file("screen-send-proof.md", markdown);
complete(#{
    path: path,
    summary: reports.len().to_string() + " platform reports",
    platforms: available,
});
