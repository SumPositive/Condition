// compose.swift
// fastlane snapshot の画面写真に、言葉と背景を付けて App Store 用の画像を作る
//
// 使い方（リポジトリ直下で）:
//   xcrun swift Scripts/StoreScreenshots/compose.swift [--theme dark|light] [--only ja] [--out フォルダ]
// 入力: fastlane/screenshots/<言語>/<機種>-<カット>.png
// 出力: fastlane/screenshots_store/<言語>/<機種>-<番号><名前>.png
//
// 文字組みは HTML(WebKit) に任せ、書き出しは App Store の指定サイズ・透過なしにそろえる

import AppKit
import WebKit

// MARK: - 内容

/// 1枚分の言葉
struct Copy { let tab, title, text: String }

/// 場面（並び順がそのまま App Store の並び順になる）
enum Scene: Int, CaseIterable {
    case records, trends, stats, symptoms

    var fileName: String { ["01Records", "02Trends", "03Stats", "04Symptoms"][rawValue] }
    /// 取扱説明の前段と同じ色
    var tone: String { ["#b3403d", "#7a4fc4", "#1f6fd1", "#b85c00"][rawValue] }
    /// 画面全体を見せる場合の元画像。nil なら図表パネルを切り抜く
    var screen: String? { [Optional("01Records"), "02Graph", nil, nil][rawValue] }
}

/// 折り返してよい位置は <wbr> で示す
let copies: [String: [Copy]] = [
    "ja": [
        Copy(tab: "記録", title: "さっと残せる", text: "「記録」を押して、<wbr>数値を入れるだけ。<wbr>頭痛などの症状も、<wbr>同じ一覧に並びます"),
        Copy(tab: "推移", title: "変化が<wbr>ひと目でわかる", text: "血圧や体重の動きを、<wbr>1週間から1年まで<wbr>グラフで見られます"),
        Copy(tab: "統計", title: "自分の傾向が<wbr>見える", text: "血圧の分布や<wbr>基準との割合を、<wbr>自動で集計します"),
        Copy(tab: "症状", title: "症状を<wbr>振り返れる", text: "気温・気圧や<wbr>直前の状況と並べて、<wbr>どんなときに起きたかを<wbr>見返せます"),
    ],
    "en-US": [
        Copy(tab: "Records", title: "Log it in seconds", text: "Tap Record and enter your numbers. Symptoms such as headaches appear in the same list."),
        Copy(tab: "Trends", title: "See changes at a glance", text: "Follow blood pressure and weight on graphs, from one week to one year."),
        Copy(tab: "Stats", title: "Know your patterns", text: "Blood pressure distribution and category ratios are worked out for you."),
        Copy(tab: "Symptoms", title: "Look back on symptoms", text: "See when they happened, alongside temperature, pressure, and what came before."),
    ],
    "ko": [
        Copy(tab: "기록", title: "빠르게 남기기", text: "\"기록\"을 누르고 수치를 입력하기만 하면 됩니다. 두통 같은 증상도 같은 목록에 표시됩니다"),
        Copy(tab: "추이", title: "변화를 한눈에", text: "혈압과 체중의 움직임을 1주부터 1년까지 그래프로 볼&nbsp;수&nbsp;있습니다"),
        Copy(tab: "통계", title: "나의 경향 파악", text: "혈압 분포와 기준별 비율을 자동으로 집계합니다"),
        Copy(tab: "증상", title: "증상을 돌아보기", text: "기온·기압, 직전 상황과 함께 언제 어떤 때 나타났는지 돌아볼&nbsp;수&nbsp;있습니다"),
    ],
    "zh-Hant": [
        Copy(tab: "記錄", title: "快速記下", text: "點選「記錄」<wbr>並輸入數值即可。<wbr>頭痛等症狀<wbr>也會顯示在同一份清單中"),
        Copy(tab: "趨勢", title: "變化一目了然", text: "以圖表查看<wbr>血壓與體重的變化，<wbr>期間從&nbsp;1&nbsp;週到&nbsp;1&nbsp;年"),
        Copy(tab: "統計", title: "看見自己的傾向", text: "自動統計血壓分布<wbr>與各基準的比例"),
        Copy(tab: "症狀", title: "回顧症狀", text: "與氣溫、氣壓及<wbr>發作前的狀況對照，<wbr>回顧何時、<wbr>在什麼情況下發作"),
    ],
]

/// 切り抜くパネル（元のカット名と、上から何番目か。-1 は最後）
struct Panel { let shot: String; let index: Int }

/// 機種ごとの大きさと配置（数値は書き出し画像のピクセル）
struct Device {
    let name: String
    let width, height: Int
    let pad, pill, title, body: Int       // 余白と文字の大きさ
    let textHeight: Int                   // 文字部分の最低の高さ（4枚で端末の位置をそろえる）
    let screenWidth, bezel, radius: Int   // 端末の幅・縁の太さ・角丸
    let panelWidth, panelRadius: Int
    let probeX: Double                    // パネルを探す列（左端のすぐ内側）
    let top, bottom: Double               // パネルを探す縦の範囲
    let stats, symptoms: [Panel]
}

let devices = [
    Device(name: "iPhone 17 Pro Max", width: 1320, height: 2868,
           pad: 96, pill: 54, title: 116, body: 58, textHeight: 780,
           screenWidth: 1100, bezel: 24, radius: 150,
           panelWidth: 1150, panelRadius: 64,
           probeX: 0.046, top: 0.12, bottom: 0.90,
           stats: [Panel(shot: "03Statistics", index: 0), Panel(shot: "03Statistics", index: 1)],
           symptoms: [Panel(shot: "05SymptomFactors", index: -1), Panel(shot: "04Symptoms", index: 1)]),
    Device(name: "iPad Pro 13-inch (M5)", width: 2064, height: 2752,
           pad: 150, pill: 66, title: 160, body: 72, textHeight: 900,
           screenWidth: 1680, bezel: 40, radius: 90,
           panelWidth: 1880, panelRadius: 56,
           probeX: 0.022, top: 0.10, bottom: 0.975,
           stats: [Panel(shot: "03Statistics", index: 0)],
           // 05 は言語で送り位置がずれ、上のパネルが切れることがあるので最後のパネルだけ使う
           symptoms: [Panel(shot: "04Symptoms", index: 0), Panel(shot: "05SymptomFactors", index: -1)]),
    Device(name: "iPhone Duo", width: 1398, height: 2034,
           pad: 100, pill: 44, title: 100, body: 46, textHeight: 590,
           screenWidth: 1080, bezel: 24, radius: 110,
           panelWidth: 1090, panelRadius: 60,
           probeX: 0.046, top: 0.02, bottom: 1.0,
           stats: [Panel(shot: "03Statistics", index: 0)],
           symptoms: [Panel(shot: "05SymptomFactors", index: -1)]),
]

// MARK: - 引数

func option(_ name: String) -> String? {
    guard let i = CommandLine.arguments.firstIndex(of: name),
          i + 1 < CommandLine.arguments.count else { return nil }
    return CommandLine.arguments[i + 1]
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let source = root.appendingPathComponent("fastlane/screenshots")
let output = option("--out").map { URL(fileURLWithPath: $0) }
    ?? root.appendingPathComponent("fastlane/screenshots_store")
let theme = option("--theme") ?? "dark"
let locales = option("--only").map { [$0] } ?? ["ja", "en-US", "ko", "zh-Hant"]
let work = FileManager.default.temporaryDirectory
    .appendingPathComponent("store-screenshots-\(ProcessInfo.processInfo.processIdentifier)")
try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)

// MARK: - 画像

func loadImage(_ url: URL) -> CGImage {
    guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
        fail("元の画面写真がありません: \(url.path)\n先に fastlane screenshots を実行してください")
    }
    return image
}

func writePNG(_ image: CGImage, _ url: URL) {
    guard let dst = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
        fail("書き出せません: \(url.path)")
    }
    CGImageDestinationAddImage(dst, image, nil)
    guard CGImageDestinationFinalize(dst) else { fail("書き出せません: \(url.path)") }
}

/// 透過なしの決まった大きさへ描き直す
func flatten(_ image: CGImage, width: Int, height: Int) -> CGImage {
    let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    ctx.interpolationQuality = .high
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    return ctx.makeImage()!
}

/// 白地に並ぶ図表パネルの範囲を、上から順に返す
func panelRects(_ image: CGImage, _ d: Device) -> [CGRect] {
    let w = image.width, h = image.height
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    let p = ctx.data!.bindMemory(to: UInt8.self, capacity: w * h * 4)
    func inside(_ x: Int, _ y: Int) -> Bool {
        let i = (y * w + x) * 4
        return min(p[i], p[i + 1], p[i + 2]) < 250
    }
    let x = Int(Double(w) * d.probeX)
    let first = Int(Double(h) * d.top), last = Int(Double(h) * d.bottom)
    var runs: [(Int, Int)] = []
    var start: Int?
    for y in first...last {
        let on = y < last && inside(x, y)
        if on, start == nil { start = y }
        if !on, let s = start { runs.append((s, y)); start = nil }
    }
    // 期間の切り替えなど低いもの、上端で切れているものは除く
    runs = runs.filter { Double(h) * 0.08 < Double($0.1 - $0.0) && first < $0.0 }
    return runs.map { top, bottom in
        // 角丸と白い入力欄を避けた高さ（見出しの行）で左右の端を探す
        let y = top + 60
        var left = x, right = x
        while 0 < left, inside(left - 1, y) { left -= 1 }
        while right < w - 1, inside(right + 1, y) { right += 1 }
        return CGRect(x: left, y: top, width: right - left + 1, height: bottom - top)
    }
}

// MARK: - HTML

func html(_ scene: Scene, _ d: Device, _ locale: String) -> String {
    let copy = copies[locale]![scene.rawValue]
    func shot(_ name: String) -> URL { source.appendingPathComponent("\(locale)/\(d.name)-\(name).png") }
    var view = ""
    if let name = scene.screen {
        // 別ボリュームの画像は WebKit が読めないことがあるので、作業フォルダへ写す
        let file = "\(locale)-\(d.width)-\(scene.rawValue).png"
        writePNG(loadImage(shot(name)), work.appendingPathComponent(file))
        view = "<div class='screen'><img src='\(file)'></div>"
    } else {
        for (i, panel) in (scene == .stats ? d.stats : d.symptoms).enumerated() {
            let image = loadImage(shot(panel.shot))
            let rects = panelRects(image, d)
            let index = panel.index < 0 ? rects.count - 1 : panel.index
            guard rects.indices.contains(index) else {
                fail("図表パネルが見つかりません: \(locale) \(d.name)-\(panel.shot) の \(panel.index) 番目（検出 \(rects.count) 個）")
            }
            let file = "\(locale)-\(d.width)-\(scene.rawValue)-\(i).png"
            writePNG(image.cropping(to: rects[index])!, work.appendingPathComponent(file))
            view += "<div class='panel'><img src='\(file)'></div>"
        }
    }
    // パネルは1枚ごとに逆へ傾ける（統計と症状でも向きを変える）
    let tilt = scene == .stats ? -2 : 2
    let base = theme == "dark" ? "#2c2c2e" : "#ffffff"
    // 英語の見出しは長いので、1行に収まる大きさにする
    let title = locale == "en-US" ? Int(Double(d.title) * 0.8) : d.title
    let ink = theme == "dark" ? "#ffffff" : "#1d1d1f"
    return """
    <!DOCTYPE html><html lang="\(locale)"><meta charset="utf-8"><style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    html, body { width: \(d.width)px; height: \(d.height)px; overflow: hidden; }
    body {
      --tone: \(scene.tone);
      font-family: -apple-system, "Hiragino Sans", sans-serif;
      color: \(ink);
      background: linear-gradient(180deg,
        color-mix(in srgb, var(--tone) 15%, \(base)) 0%,
        color-mix(in srgb, var(--tone) 22%, \(base)) 34%,
        color-mix(in srgb, var(--tone) 52%, \(base)) 100%);
      word-break: keep-all; overflow-wrap: anywhere;
    }
    .text { min-height: \(d.textHeight)px; padding: \(Int(Double(d.pad) * 1.3))px \(d.pad)px \(Int(Double(d.pad) * 0.5))px; }
    .tab {
      display: inline-block; padding: .28em .95em; border-radius: 9em;
      background: var(--tone); color: #fff; font-size: \(d.pill)px; font-weight: 700; line-height: 1.35;
    }
    h1 { margin-top: .3em; font-size: \(title)px; font-weight: 800; line-height: 1.25; text-wrap: balance; }
    p { margin-top: .5em; font-size: \(d.body)px; font-weight: 500; line-height: 1.5; text-wrap: balance; }
    img { display: block; width: 100%; }
    .screen {
      width: \(d.screenWidth)px; margin: 0 auto; overflow: hidden; background: #fff;
      border: \(d.bezel)px solid #1d1d1f; border-radius: \(d.radius)px;
      box-shadow: 0 0 0 3px rgba(255,255,255,.22), 0 30px 90px rgba(0,0,0,.45);
    }
    .panel {
      position: relative; width: \(d.panelWidth)px; margin: 0 auto \(d.pad / 2)px; overflow: hidden;
      border-radius: \(d.panelRadius)px; box-shadow: 0 24px 80px rgba(0,0,0,.4);
      transform: rotate(\(tilt)deg);
    }
    .panel + .panel { transform: rotate(\(-tilt)deg); }
    </style><body>
    <div class="text"><span class="tab">\(copy.tab)</span><h1>\(copy.title)</h1><p>\(copy.text)</p></div>
    <main>\(view)</main>
    </body></html>
    """
}

// MARK: - 書き出し

/// 1枚ずつ順に読み込んで撮る
final class Renderer: NSObject, WKNavigationDelegate {
    private var jobs: [(Scene, Device, String)] = []
    private let web = WKWebView(frame: .zero)
    private var count = 0

    override init() {
        super.init()
        web.navigationDelegate = self
        for locale in locales {
            guard copies[locale] != nil else { fail("未対応の言語です: \(locale)") }
            for d in devices { for s in Scene.allCases { jobs.append((s, d, locale)) } }
        }
    }

    func next() {
        guard let (scene, d, locale) = jobs.first else {
            try? FileManager.default.removeItem(at: work)
            print("\(count) 枚を書き出しました: \(output.path)")
            exit(0)
        }
        web.setFrameSize(NSSize(width: d.width, height: d.height))
        let page = work.appendingPathComponent("page.html")
        try! html(scene, d, locale).write(to: page, atomically: true, encoding: .utf8)
        web.loadFileURL(page, allowingReadAccessTo: work)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let (scene, d, locale) = jobs.removeFirst()
        // 文字が想定より高いと端末の位置がずれるので知らせる。画像の読み込み漏れは失敗にする
        let js = """
        [[...document.images].every(i => i.complete && 0 < i.naturalWidth),
         document.querySelector('.text').offsetHeight]
        """
        webView.evaluateJavaScript(js) { result, _ in
            let values = result as? [Any] ?? []
            guard values.first as? Bool == true else { fail("画像を読み込めません: \(locale) \(d.name) \(scene.fileName)") }
            if let height = values.last as? Int, d.textHeight < height {
                print("注意: 文字が \(height - d.textHeight)px はみ出して端末が下がります: \(locale) \(d.name) \(scene.fileName)")
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                webView.takeSnapshot(with: nil) { image, error in
                    guard let cg = image?.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                        fail("撮影に失敗しました: \(String(describing: error))")
                    }
                    let dir = output.appendingPathComponent(locale)
                    try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                    writePNG(flatten(cg, width: d.width, height: d.height),
                             dir.appendingPathComponent("\(d.name)-\(scene.fileName).png"))
                    self.count += 1
                    self.next()
                }
            }
        }
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
let renderer = Renderer()
renderer.next()
app.run()
