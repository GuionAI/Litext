//
//  Created by Lakr233 & Helixform on 2025/2/18.
//  Copyright (c) 2025 Litext Team. All rights reserved.
//

import CoreGraphics
import CoreText
import Foundation
import QuartzCore

private func _hasHighlightAttributes(_ attributes: [NSAttributedString.Key: Any]) -> Bool {
    if attributes[.link] != nil {
        return true
    }
    if attributes[LTXAttachmentAttributeName] != nil {
        return true
    }
    if attributes[LTXHighlightAttributeName] != nil {
        return true
    }
    return false
}

@MainActor
public class LTXTextLayout: NSObject {
    private let core: LTXTextLayoutCore
    private var _highlightRegions: [Int: LTXHighlightRegion]

    public var attributedString: NSAttributedString {
        core.attributedString
    }

    public var highlightRegions: [LTXHighlightRegion] {
        Array(_highlightRegions.values)
    }

    public var containerSize: CGSize {
        didSet {
            core.containerSize = containerSize
        }
    }

    var ctFrame: CTFrame? {
        core.ctFrame
    }

    public class func textLayout(
        withAttributedString attributedString: NSAttributedString
    ) -> LTXTextLayout {
        LTXTextLayout(attributedString: attributedString)
    }

    public init(attributedString: NSAttributedString) {
        core = LTXTextLayoutCore(attributedString: attributedString)
        containerSize = .zero
        _highlightRegions = [:]
        super.init()
    }

    public func invalidateLayout() {
        core.invalidateLayout()
    }

    public func suggestContainerSize(withSize size: CGSize) -> CGSize {
        core.suggestContainerSize(withSize: size)
    }

    public func suggestVisualContainerSize(withSize size: CGSize) -> CGSize {
        core.suggestVisualContainerSize(withSize: size)
    }

    public func draw(in context: CGContext) {
        context.saveGState()

        context.setAllowsAntialiasing(true)
        context.setShouldSmoothFonts(true)

        context.translateBy(x: 0, y: containerSize.height)
        context.scaleBy(x: 1, y: -1)

        core.drawTextBackgroundBorders(in: context)
        if let ctFrame { CTFrameDraw(ctFrame, context) }
        processLineDrawingActions(in: context)

        context.restoreGState()
    }

    public func updateHighlightRegions() {
        _highlightRegions.removeAll()
        extractHighlightRegions()
    }

    public func rects(for range: NSRange) -> [CGRect] {
        core.rects(for: range)
    }

    public func enumerateTextRects(in range: NSRange, using block: (CGRect) -> Void) {
        core.rects(for: range).forEach(block)
    }

    public func textIndex(at point: CGPoint) -> Int? {
        core.textIndex(at: point)
    }

    public func nearestTextIndex(at point: CGPoint) -> Int? {
        core.nearestTextIndex(at: point)
    }

    private func processLineDrawingActions(in context: CGContext) {
        core.enumerateLines { line, _, lineOrigin in
            let glyphRuns = CTLineGetGlyphRuns(line) as NSArray

            for i in 0 ..< glyphRuns.count {
                guard let glyphRun = glyphRuns[i] as! CTRun?
                else { continue }

                let attributes = CTRunGetAttributes(glyphRun) as! [NSAttributedString.Key: Any]
                if let action = attributes[LTXLineDrawingCallbackName] as? LTXLineDrawingAction {
                    context.saveGState()
                    action.action(context, line, lineOrigin)
                    context.restoreGState()
                }
            }
        }
    }

    private func extractHighlightRegions() {
        core.enumerateLines { line, _, lineOrigin in
            let glyphRuns = CTLineGetGlyphRuns(line) as NSArray

            for i in 0 ..< glyphRuns.count {
                guard let glyphRun = glyphRuns[i] as! CTRun? else { continue }

                let attributes = CTRunGetAttributes(
                    glyphRun
                ) as! [NSAttributedString.Key: Any]
                if !_hasHighlightAttributes(attributes) {
                    continue
                }

                processHighlightRegionForRun(
                    glyphRun,
                    attributes: attributes,
                    lineOrigin: lineOrigin
                )
            }
        }
    }

    private func processHighlightRegionForRun(
        _ glyphRun: CTRun,
        attributes: [NSAttributedString.Key: Any],
        lineOrigin: CGPoint
    ) {
        let cfStringRange = CTRunGetStringRange(glyphRun)
        let stringRange = NSRange(
            location: cfStringRange.location,
            length: cfStringRange.length
        )

        var effectiveRange = NSRange()
        _ = attributedString.attributes(
            at: stringRange.location,
            effectiveRange: &effectiveRange
        )

        let highlightRegion: LTXHighlightRegion
        if let existingRegion = _highlightRegions[effectiveRange.location] {
            highlightRegion = existingRegion
        } else {
            highlightRegion = LTXHighlightRegion(
                attributes: attributes,
                stringRange: stringRange
            )
            _highlightRegions[effectiveRange.location] = highlightRegion
        }

        var runBounds = CTRunGetImageBounds(
            glyphRun,
            nil,
            CFRange(location: 0, length: 0)
        )

        if let attachment = attributes[LTXAttachmentAttributeName] as? LTXAttachment {
            runBounds.size = attachment.size
            runBounds.origin.y -= attachment.descentOverride ?? attachment.size.height * 0.1
        }

        runBounds.origin.x += lineOrigin.x
        runBounds.origin.y += lineOrigin.y
        highlightRegion.addRect(runBounds)
    }
}
