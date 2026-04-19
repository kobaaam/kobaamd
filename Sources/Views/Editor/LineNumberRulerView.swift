import AppKit

final class LineNumberRulerView: NSRulerView {
    private weak var textView: NSTextView?

    override var isFlipped: Bool { true }

    init(textView: NSTextView) {
        guard let scrollView = textView.enclosingScrollView else {
            fatalError("NSTextView must be in an NSScrollView before creating LineNumberRulerView")
        }
        super.init(scrollView: scrollView, orientation: .verticalRuler)
        self.clientView = textView
        self.textView = textView
        ruleThickness = 44
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not implemented") }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let textView,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else { return }

        NSColor.windowBackgroundColor.setFill()
        rect.fill()

        // Right border
        let path = NSBezierPath()
        path.move(to: NSPoint(x: bounds.maxX - 0.5, y: rect.minY))
        path.line(to: NSPoint(x: bounds.maxX - 0.5, y: rect.maxY))
        path.lineWidth = 1
        NSColor.separatorColor.setStroke()
        path.stroke()

        // Build line-start → line number map
        let nsString = textView.string as NSString
        var lineStarts: [Int: Int] = [0: 1]
        var idx = 0, lineNum = 2
        while idx < nsString.length {
            let ch = nsString.character(at: idx)
            if ch == 0x0A || ch == 0x0D {
                var next = idx + 1
                if ch == 0x0D && next < nsString.length && nsString.character(at: next) == 0x0A { next += 1 }
                if lineStarts[next] == nil { lineStarts[next] = lineNum }
                lineNum += 1
                idx = next
            } else { idx += 1 }
        }

        let font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .right
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: paragraphStyle
        ]
        let labelWidth = bounds.width - 8
        let origin = textView.textContainerOrigin

        let visibleRange = layoutManager.glyphRange(forBoundingRect: textView.visibleRect, in: textContainer)
        layoutManager.enumerateLineFragments(forGlyphRange: visibleRange) { _, usedRect, _, glyphRange, _ in
            let charRange = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
            guard charRange.location != NSNotFound, let ln = lineStarts[charRange.location] else { return }
            let label = "\(ln)"
            let sz = label.size(withAttributes: attrs)
            let yInView = self.convert(NSPoint(x: 0, y: origin.y + usedRect.minY), from: textView).y
            let textRect = NSRect(x: 2, y: yInView + (usedRect.height - sz.height) / 2, width: labelWidth, height: sz.height)
            label.draw(in: textRect, withAttributes: attrs)
        }
    }

    static func install(on scrollView: NSScrollView, textView: NSTextView) {
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = true
        scrollView.verticalRulerView = LineNumberRulerView(textView: textView)
    }
}
