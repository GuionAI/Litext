//
//  LTXTextBackgroundBorder.swift
//  Litext
//
//  Created by Codex on 2026/6/22.
//

import CoreGraphics
import Foundation

public struct LTXTextBackgroundBorderInsets: Equatable, Sendable {
    public var top: CGFloat
    public var left: CGFloat
    public var bottom: CGFloat
    public var right: CGFloat

    public init(top: CGFloat = 0, left: CGFloat = 0, bottom: CGFloat = 0, right: CGFloat = 0) {
        self.top = top
        self.left = left
        self.bottom = bottom
        self.right = right
    }
}

public struct LTXTextBackgroundBorder: Equatable {
    public var fillColor: CGColor?
    public var strokeColor: CGColor?
    public var lineWidth: CGFloat
    public var cornerRadius: CGFloat
    public var insets: LTXTextBackgroundBorderInsets
    public var fixedHeight: CGFloat?
    public var verticalOffset: CGFloat

    public init(
        fillColor: CGColor? = nil,
        strokeColor: CGColor? = nil,
        lineWidth: CGFloat = 0,
        cornerRadius: CGFloat = 0,
        insets: LTXTextBackgroundBorderInsets = .init(),
        fixedHeight: CGFloat? = nil,
        verticalOffset: CGFloat = 0
    ) {
        self.fillColor = fillColor
        self.strokeColor = strokeColor
        self.lineWidth = lineWidth
        self.cornerRadius = cornerRadius
        self.insets = insets
        self.fixedHeight = fixedHeight
        self.verticalOffset = verticalOffset
    }
}

public struct LTXTextBackgroundBorderRegion {
    public let range: NSRange
    public let border: LTXTextBackgroundBorder
    public let rects: [CGRect]
}

enum LTXTextBackgroundBorderDrawing {
    static func draw(_ regions: [LTXTextBackgroundBorderRegion], in context: CGContext) {
        for region in regions {
            for rect in region.rects {
                draw(region.border, rect: rect, in: context)
            }
        }
    }

    private static func draw(_ border: LTXTextBackgroundBorder, rect: CGRect, in context: CGContext) {
        guard border.fillColor != nil || border.strokeColor != nil else { return }
        guard rect.width > 0, rect.height > 0 else { return }

        let cornerRadius = min(border.cornerRadius, rect.height / 2)
        let path = CGPath(
            roundedRect: rect,
            cornerWidth: cornerRadius,
            cornerHeight: cornerRadius,
            transform: nil
        )

        context.saveGState()
        context.addPath(path)

        if let fillColor = border.fillColor {
            context.setFillColor(fillColor)
            context.fillPath()
        }

        if let strokeColor = border.strokeColor, border.lineWidth > 0 {
            context.addPath(path)
            context.setStrokeColor(strokeColor)
            context.setLineWidth(border.lineWidth)
            context.strokePath()
        }

        context.restoreGState()
    }
}

extension CGRect {
    func expanding(_ insets: LTXTextBackgroundBorderInsets) -> CGRect {
        CGRect(
            x: origin.x - insets.left,
            y: origin.y - insets.bottom,
            width: width + insets.left + insets.right,
            height: height + insets.top + insets.bottom
        )
    }
}
