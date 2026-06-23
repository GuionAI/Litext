//
//  LTXTextLayoutCore.swift
//  Litext
//
//  Created by Codex on 2026/6/22.
//

import CoreGraphics
import CoreText
import Foundation

public final class LTXTextLayoutCore {
    public let attributedString: NSAttributedString
    public var containerSize: CGSize {
        didSet {
            generateLayout()
        }
    }

    let framesetter: CTFramesetter
    private(set) var ctFrame: CTFrame?
    private var lines: [CTLine]?

    public init(attributedString: NSAttributedString) {
        self.attributedString = attributedString
        containerSize = .zero
        framesetter = CTFramesetterCreateWithAttributedString(attributedString)
    }

    public func invalidateLayout() {
        generateLayout()
    }

    public func suggestContainerSize(withSize size: CGSize) -> CGSize {
        CTFramesetterSuggestFrameSizeWithConstraints(
            framesetter,
            CFRange(location: 0, length: 0),
            nil,
            size,
            nil
        )
    }

    public func suggestVisualContainerSize(withSize size: CGSize) -> CGSize {
        var suggestedSize = suggestContainerSize(withSize: size)
        guard suggestedSize.height > 0 else { return suggestedSize }

        let previousContainerSize = containerSize
        defer { containerSize = previousContainerSize }

        let width = size.width.isFinite ? size.width : suggestedSize.width
        containerSize = CGSize(
            width: max(width, 1),
            height: max(ceil(suggestedSize.height), 1)
        )

        let rects = backgroundBorderRegions().flatMap(\.rects)
        guard !rects.isEmpty else { return suggestedSize }

        let minY = rects.reduce(CGFloat(0)) { min($0, $1.minY) }
        let maxY = rects.reduce(containerSize.height) { max($0, $1.maxY) }
        suggestedSize.height += max(0, -minY)
        suggestedSize.height += max(0, maxY - containerSize.height)
        return suggestedSize
    }

    public func rects(for range: NSRange) -> [CGRect] {
        var rects = [CGRect]()
        enumerateTextRects(in: range) { rect in
            rects.append(rect)
        }
        return rects
    }

    public func backgroundBorderRegions() -> [LTXTextBackgroundBorderRegion] {
        var regionsByLocation: [Int: (range: NSRange, border: LTXTextBackgroundBorder, rects: [CGRect])] = [:]

        enumerateLines { line, _, lineOrigin in
            let glyphRuns = CTLineGetGlyphRuns(line) as NSArray

            for i in 0 ..< glyphRuns.count {
                guard let glyphRun = glyphRuns[i] as! CTRun? else { continue }
                let attributes = CTRunGetAttributes(glyphRun) as! [NSAttributedString.Key: Any]
                guard let border = attributes[.ltxTextBackgroundBorder] as? LTXTextBackgroundBorder else {
                    continue
                }

                let cfRange = CTRunGetStringRange(glyphRun)
                guard cfRange.location != kCFNotFound, cfRange.length > 0 else { continue }

                var effectiveRange = NSRange()
                _ = attributedString.attributes(
                    at: cfRange.location,
                    effectiveRange: &effectiveRange
                )

                let rect = backgroundBorderRect(
                    for: glyphRun,
                    in: line,
                    lineOrigin: lineOrigin,
                    border: border
                )
                guard rect.width > 0, rect.height > 0 else { continue }

                var region = regionsByLocation[effectiveRange.location] ?? (
                    range: effectiveRange,
                    border: border,
                    rects: []
                )
                region.rects.append(rect)
                regionsByLocation[effectiveRange.location] = region
            }
        }

        return regionsByLocation
            .sorted { $0.key < $1.key }
            .map {
                LTXTextBackgroundBorderRegion(
                    range: $0.value.range,
                    border: $0.value.border,
                    rects: $0.value.rects
                )
            }
    }

    public func textIndex(at point: CGPoint) -> Int? {
        guard let ctFrame else { return nil }

        if let lineInfo = findLineContainingPoint(point, ctFrame: ctFrame) {
            return findCharacterIndexInLine(point, lineInfo: lineInfo)
        }

        let lines = CTFrameGetLines(ctFrame) as [AnyObject]
        guard !lines.isEmpty else { return nil }
        var lineOrigins = [CGPoint](repeating: .zero, count: lines.count)
        CTFrameGetLineOrigins(ctFrame, CFRange(location: 0, length: 0), &lineOrigins)

        guard point.y < lineOrigins[lines.count - 1].y else { return nil }
        let lastLine = lines[lines.count - 1] as! CTLine
        let range = CTLineGetStringRange(lastLine)
        return range.location + range.length
    }

    public func nearestTextIndex(at point: CGPoint) -> Int? {
        guard let ctFrame else { return nil }

        if let lineInfo = findLineContainingPoint(point, ctFrame: ctFrame) {
            return findCharacterIndexInLine(point, lineInfo: lineInfo)
        }

        let lines = CTFrameGetLines(ctFrame) as [AnyObject]
        guard !lines.isEmpty else { return nil }

        var lineOrigins = [CGPoint](repeating: .zero, count: lines.count)
        CTFrameGetLineOrigins(ctFrame, CFRange(location: 0, length: 0), &lineOrigins)

        if point.y > lineOrigins[0].y {
            let firstLine = lines[0] as! CTLine
            if point.x < lineOrigins[0].x {
                return CTLineGetStringRange(firstLine).location
            }

            let range = CTLineGetStringRange(firstLine)
            let lineWidth = CTLineGetTypographicBounds(firstLine, nil, nil, nil)
            if point.x > lineOrigins[0].x + lineWidth {
                return range.location + range.length
            }
            return findCharacterIndexInLine(point, lineInfo: (firstLine, lineOrigins[0], 0))
        }

        if point.y < lineOrigins[lines.count - 1].y {
            let lastLine = lines[lines.count - 1] as! CTLine
            if point.x < lineOrigins[lines.count - 1].x {
                return CTLineGetStringRange(lastLine).location
            }

            let range = CTLineGetStringRange(lastLine)
            let lineWidth = CTLineGetTypographicBounds(lastLine, nil, nil, nil)
            if point.x > lineOrigins[lines.count - 1].x + lineWidth {
                return range.location + range.length
            }
            return findCharacterIndexInLine(
                point,
                lineInfo: (lastLine, lineOrigins[lines.count - 1], lines.count - 1)
            )
        }

        var closestLineIndex = 0
        var minDistance = CGFloat.greatestFiniteMagnitude

        for i in 0 ..< lines.count {
            let line = lines[i] as! CTLine
            let origin = lineOrigins[i]
            var ascent: CGFloat = 0
            var descent: CGFloat = 0
            var leading: CGFloat = 0

            CTLineGetTypographicBounds(line, &ascent, &descent, &leading)

            let lineMiddleY = origin.y - descent + (ascent + descent) / 2
            let distance = abs(point.y - lineMiddleY)

            if distance < minDistance {
                minDistance = distance
                closestLineIndex = i
            }
        }

        let closestLine = lines[closestLineIndex] as! CTLine
        let closestOrigin = lineOrigins[closestLineIndex]
        return findCharacterIndexInLine(
            point,
            lineInfo: (closestLine, closestOrigin, closestLineIndex)
        )
    }

    func drawTextBackgroundBorders(in context: CGContext) {
        LTXTextBackgroundBorderDrawing.draw(backgroundBorderRegions(), in: context)
    }

    func enumerateLines(
        using block: (CTLine, Int, CGPoint) -> Void
    ) {
        guard let lines, let ctFrame else { return }

        let lineCount = lines.count
        var lineOrigins = [CGPoint](repeating: .zero, count: lineCount)
        CTFrameGetLineOrigins(
            ctFrame,
            CFRange(location: 0, length: 0),
            &lineOrigins
        )

        for i in 0 ..< lineCount {
            block(lines[i], i, lineOrigins[i])
        }
    }

    private func enumerateTextRects(in range: NSRange, using block: (CGRect) -> Void) {
        guard let ctFrame else { return }

        let lines = CTFrameGetLines(ctFrame) as NSArray
        let lineCount = lines.count
        var origins = [CGPoint](repeating: .zero, count: lineCount)
        CTFrameGetLineOrigins(ctFrame, CFRange(location: 0, length: 0), &origins)

        for i in 0 ..< lineCount {
            let line = lines[i] as! CTLine
            let lineRange = CTLineGetStringRange(line)

            let lineStart = lineRange.location
            let lineEnd = lineStart + lineRange.length
            let selStart = range.location
            let selEnd = selStart + range.length

            if selEnd < lineStart || selStart > lineEnd {
                continue
            }

            let overlapStart = max(lineStart, selStart)
            let overlapEnd = min(lineEnd, selEnd)

            if overlapStart >= overlapEnd {
                continue
            }

            calculateAndAddTextRect(
                for: line,
                origin: origins[i],
                overlapStart: overlapStart,
                overlapEnd: overlapEnd,
                lineStart: lineStart,
                lineEnd: lineEnd,
                using: block
            )
        }
    }

    private func calculateAndAddTextRect(
        for line: CTLine,
        origin: CGPoint,
        overlapStart: CFIndex,
        overlapEnd: CFIndex,
        lineStart: CFIndex,
        lineEnd: CFIndex,
        using block: (CGRect) -> Void
    ) {
        var startOffset: CGFloat = 0
        var endOffset: CGFloat = 0

        if overlapStart > lineStart {
            startOffset = CTLineGetOffsetForStringIndex(
                line,
                overlapStart,
                nil
            )
        }

        if overlapEnd < lineEnd {
            endOffset = CTLineGetOffsetForStringIndex(
                line,
                overlapEnd,
                nil
            )
        } else {
            endOffset = CTLineGetTypographicBounds(
                line,
                nil,
                nil,
                nil
            )
        }

        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        var leading: CGFloat = 0
        CTLineGetTypographicBounds(
            line,
            &ascent,
            &descent,
            &leading
        )

        block(CGRect(
            x: origin.x + startOffset,
            y: origin.y - descent,
            width: endOffset - startOffset,
            height: ascent + descent + leading
        ))
    }

    private func backgroundBorderRect(
        for glyphRun: CTRun,
        in line: CTLine,
        lineOrigin: CGPoint,
        border: LTXTextBackgroundBorder
    ) -> CGRect {
        let cfRange = CTRunGetStringRange(glyphRun)
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        var leading: CGFloat = 0
        let width = CGFloat(CTRunGetTypographicBounds(
            glyphRun,
            CFRange(location: 0, length: 0),
            &ascent,
            &descent,
            &leading
        ))

        let x = lineOrigin.x + CTLineGetOffsetForStringIndex(line, cfRange.location, nil)
        var rect = CGRect(
            x: x,
            y: lineOrigin.y - descent,
            width: width,
            height: ascent + descent + leading
        )

        if let fixedHeight = border.fixedHeight {
            rect.origin.y += (rect.height - fixedHeight) / 2
            rect.size.height = fixedHeight
        }
        rect.origin.y += border.verticalOffset
        return rect.expanding(border.insets)
    }

    private func generateLayout() {
        lines = nil

        let containerBounds = CGRect(
            origin: .zero,
            size: containerSize
        )
        let containerPath = CGPath(
            rect: containerBounds,
            transform: nil
        )
        ctFrame = CTFramesetterCreateFrame(
            framesetter,
            CFRange(location: 0, length: 0),
            containerPath,
            nil
        )

        if let ctFrame {
            lines = CTFrameGetLines(ctFrame) as? [CTLine]
        }
    }

    private func findLineContainingPoint(
        _ point: CGPoint,
        ctFrame: CTFrame
    ) -> (line: CTLine, origin: CGPoint, index: Int)? {
        let lines = CTFrameGetLines(ctFrame) as [AnyObject]
        var lineOrigins = [CGPoint](repeating: .zero, count: lines.count)
        CTFrameGetLineOrigins(ctFrame, CFRange(location: 0, length: 0), &lineOrigins)

        for i in 0 ..< lines.count {
            let origin = lineOrigins[i]
            var ascent: CGFloat = 0
            var descent: CGFloat = 0
            var leading: CGFloat = 0

            let line = lines[i] as! CTLine
            let lineWidth = CTLineGetTypographicBounds(line, &ascent, &descent, &leading)
            let lineHeight = ascent + descent + leading

            let lineRect = CGRect(
                x: origin.x,
                y: origin.y - descent,
                width: lineWidth,
                height: lineHeight
            )

            if point.y >= lineRect.minY, point.y <= lineRect.maxY {
                return (line: line, origin: origin, index: i)
            }
        }

        return nil
    }

    private func findCharacterIndexInLine(
        _ point: CGPoint,
        lineInfo: (line: CTLine, origin: CGPoint, index: Int)
    ) -> Int {
        let line = lineInfo.line
        let lineOrigin = lineInfo.origin
        let lineRange = CTLineGetStringRange(line)

        if point.x <= lineOrigin.x {
            return lineRange.location
        }

        for characterOffset in 0 ..< lineRange.length {
            let characterIndex = lineRange.location + characterOffset
            let positionOffset = CTLineGetOffsetForStringIndex(line, characterIndex, nil)

            if positionOffset >= point.x - lineOrigin.x {
                let distanceToNextChar = positionOffset - (point.x - lineOrigin.x)
                if characterOffset > 0 {
                    let previousCharIndex = characterIndex - 1
                    let previousPositionOffset = CTLineGetOffsetForStringIndex(line, previousCharIndex, nil)
                    let distanceToPrevChar = (point.x - lineOrigin.x) - previousPositionOffset
                    if distanceToNextChar > distanceToPrevChar {
                        return previousCharIndex
                    }
                }
                return characterIndex
            }
        }

        return lineRange.location + lineRange.length
    }
}
