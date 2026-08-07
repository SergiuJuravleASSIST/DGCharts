//
//  XAxisRenderer.swift
//  Charts
//
//  Copyright 2015 Daniel Cohen Gindi & Philipp Jahoda
//  A port of MPAndroidChart for iOS
//  Licensed under Apache License 2.0
//
//  https://github.com/ChartsOrg/Charts
//

import Foundation
import CoreGraphics

#if !os(OSX)
    import UIKit
#endif

@objc(ChartXAxisRenderer)
open class XAxisRenderer: NSObject, AxisRenderer
{
    @objc public let viewPortHandler: ViewPortHandler
    @objc public let axis: XAxis
    @objc public let transformer: Transformer?

    /// Set by BarChartRenderer before the draw cycle reaches renderAxisLabels,
    /// so the standard call routes to the player-image overload automatically.
    open var barDataSet: BarChartDataSetProtocol?

    @objc public init(viewPortHandler: ViewPortHandler, axis: XAxis, transformer: Transformer?)
    {
        self.viewPortHandler = viewPortHandler
        self.axis = axis
        self.transformer = transformer
        super.init()
    }

    open func computeAxis(min: Double, max: Double, inverted: Bool)
    {
        var min = min, max = max

        if let transformer = self.transformer,
            viewPortHandler.contentWidth > 10,
            !viewPortHandler.isFullyZoomedOutX
        {
            let p1 = transformer.valueForTouchPoint(CGPoint(x: viewPortHandler.contentLeft, y: viewPortHandler.contentTop))
            let p2 = transformer.valueForTouchPoint(CGPoint(x: viewPortHandler.contentRight, y: viewPortHandler.contentTop))
            min = inverted ? Double(p2.x) : Double(p1.x)
            max = inverted ? Double(p1.x) : Double(p2.x)
        }

        computeAxisValues(min: min, max: max)
    }

    open func computeAxisValues(min: Double, max: Double)
    {
        let yMin = min
        let yMax = max
        let labelCount = axis.labelCount
        let range = abs(yMax - yMin)

        guard labelCount != 0, range > 0, range.isFinite else {
            axis.entries = []
            axis.centeredEntries = []
            return
        }

        let rawInterval = range / Double(labelCount)
        var interval = rawInterval.roundedToNextSignificant()

        if axis.granularityEnabled {
            interval = Swift.max(interval, axis.granularity)
        }

        let intervalMagnitude = pow(10.0, Double(Int(log10(interval)))).roundedToNextSignificant()
        let intervalSigDigit = Int(interval / intervalMagnitude)
        if intervalSigDigit > 5 {
            interval = floor(10.0 * Double(intervalMagnitude))
        }

        var n = axis.centerAxisLabelsEnabled ? 1 : 0

        if axis.isForceLabelsEnabled {
            interval = range / Double(labelCount - 1)
            axis.entries.removeAll(keepingCapacity: true)
            axis.entries.reserveCapacity(labelCount)
            let values = stride(from: yMin, to: Double(labelCount) * interval + yMin, by: interval)
            axis.entries.append(contentsOf: values)
            n = labelCount
        } else {
            var first = interval == 0.0 ? 0.0 : ceil(yMin / interval) * interval
            if axis.centerAxisLabelsEnabled { first -= interval }
            let last = interval == 0.0 ? 0.0 : (floor(yMax / interval) * interval).nextUp
            if interval != 0.0, last != first {
                stride(from: first, through: last, by: interval).forEach { _ in n += 1 }
            }
            axis.entries.removeAll(keepingCapacity: true)
            axis.entries.reserveCapacity(labelCount)
            let start = first, end = first + Double(n) * interval
            let values = stride(from: start, to: end, by: interval).map { $0 == 0.0 ? 0.0 : $0 }
            axis.entries.append(contentsOf: values)
        }

        if interval < 1 { axis.decimals = Int(ceil(-log10(interval))) } else { axis.decimals = 0 }

        if axis.centerAxisLabelsEnabled {
            let offset: Double = interval / 2.0
            axis.centeredEntries = axis.entries[..<n].map { $0 + offset }
        }

        computeSize()
    }

    @objc open func computeSize()
    {
        let longest = axis.getLongestLabel()
        let labelSize = longest.size(withAttributes: [.font: axis.labelFont])
        let labelRotatedSize = labelSize.rotatedBy(degrees: axis.labelRotationAngle)
        axis.labelWidth = labelSize.width
        axis.labelHeight = labelSize.height
        axis.labelRotatedWidth = labelRotatedSize.width
        axis.labelRotatedHeight = labelRotatedSize.height
    }

    open func renderAxisLabels(context: CGContext)
    {
        guard axis.isEnabled, axis.isDrawLabelsEnabled else { return }

        if let ds = barDataSet {
            renderAxisLabels(with: context, barDataSet: ds)
            return
        }

        let yOffset = axis.yOffset

        switch axis.labelPosition {
        case .top:
            drawLabels(context: context, pos: viewPortHandler.contentTop - yOffset, anchor: CGPoint(x: 0.5, y: 1.0))
        case .topInside:
            drawLabels(context: context, pos: viewPortHandler.contentTop + yOffset + axis.labelRotatedHeight, anchor: CGPoint(x: 0.5, y: 1.0))
        case .bottom:
            drawLabels(context: context, pos: viewPortHandler.contentBottom + yOffset, anchor: CGPoint(x: 0.5, y: 0.0))
        case .bottomInside:
            drawLabels(context: context, pos: viewPortHandler.contentBottom - yOffset - axis.labelRotatedHeight, anchor: CGPoint(x: 0.5, y: 0.0))
        case .bothSided:
            drawLabels(context: context, pos: viewPortHandler.contentTop - yOffset, anchor: CGPoint(x: 0.5, y: 1.0))
            drawLabels(context: context, pos: viewPortHandler.contentBottom + yOffset, anchor: CGPoint(x: 0.5, y: 0.0))
        }
    }

    /// Renders axis labels using player image data from the bar dataset entries.
    open func renderAxisLabels(with context: CGContext, barDataSet: BarChartDataSetProtocol)
    {
        guard axis.isEnabled, axis.isDrawLabelsEnabled else { return }

        let yOffset = axis.yOffset

        switch axis.labelPosition {
        case .top:
            drawLabels(context: context, pos: viewPortHandler.contentTop - yOffset, anchor: CGPoint(x: 0.5, y: 1.0), barDataSet: barDataSet)
        case .topInside:
            drawLabels(context: context, pos: viewPortHandler.contentTop + yOffset + axis.labelRotatedHeight, anchor: CGPoint(x: 0.5, y: 1.0), barDataSet: barDataSet)
        case .bottom:
            drawLabels(context: context, pos: viewPortHandler.contentBottom + yOffset, anchor: CGPoint(x: 0.5, y: 0.0), barDataSet: barDataSet)
        case .bottomInside:
            drawLabels(context: context, pos: viewPortHandler.contentBottom - yOffset - axis.labelRotatedHeight, anchor: CGPoint(x: 0.5, y: 0.0), barDataSet: barDataSet)
        case .bothSided:
            drawLabels(context: context, pos: viewPortHandler.contentTop - yOffset, anchor: CGPoint(x: 0.5, y: 1.0), barDataSet: barDataSet)
            drawLabels(context: context, pos: viewPortHandler.contentBottom + yOffset, anchor: CGPoint(x: 0.5, y: 0.0), barDataSet: barDataSet)
        }
    }

    private var axisLineSegmentsBuffer = [CGPoint](repeating: .zero, count: 2)

    open func renderAxisLine(context: CGContext)
    {
        guard axis.isEnabled, axis.isDrawAxisLineEnabled else { return }

        context.saveGState()
        defer { context.restoreGState() }

        context.setStrokeColor(axis.axisLineColor.cgColor)
        context.setLineWidth(axis.axisLineWidth)
        if axis.axisLineDashLengths != nil {
            context.setLineDash(phase: axis.axisLineDashPhase, lengths: axis.axisLineDashLengths)
        } else {
            context.setLineDash(phase: 0.0, lengths: [])
        }

        if axis.labelPosition == .top || axis.labelPosition == .topInside || axis.labelPosition == .bothSided {
            axisLineSegmentsBuffer[0] = CGPoint(x: viewPortHandler.contentLeft, y: viewPortHandler.contentTop)
            axisLineSegmentsBuffer[1] = CGPoint(x: viewPortHandler.contentRight, y: viewPortHandler.contentTop)
            context.strokeLineSegments(between: axisLineSegmentsBuffer)
        }

        if axis.labelPosition == .bottom || axis.labelPosition == .bottomInside || axis.labelPosition == .bothSided {
            axisLineSegmentsBuffer[0] = CGPoint(x: viewPortHandler.contentLeft, y: viewPortHandler.contentBottom)
            axisLineSegmentsBuffer[1] = CGPoint(x: viewPortHandler.contentRight, y: viewPortHandler.contentBottom)
            context.strokeLineSegments(between: axisLineSegmentsBuffer)
        }
    }

    /// Draws standard x-axis labels (no player images).
    @objc open func drawLabels(context: CGContext, pos: CGFloat, anchor: CGPoint)
    {
        guard let transformer = self.transformer else { return }

        let paraStyle = ParagraphStyle.default.mutableCopy() as! MutableParagraphStyle
        paraStyle.alignment = .center

        let labelAttrs: [NSAttributedString.Key: Any] = [.font: axis.labelFont,
                                                         .foregroundColor: axis.labelTextColor,
                                                         .paragraphStyle: paraStyle]
        let labelRotationAngleRadians = axis.labelRotationAngle.DEG2RAD
        let isCenteringEnabled = axis.isCenterAxisLabelsEnabled
        let valueToPixelMatrix = transformer.valueToPixelMatrix

        var position = CGPoint.zero
        var labelMaxSize = CGSize.zero
        if axis.isWordWrapEnabled {
            labelMaxSize.width = axis.wordWrapWidthPercent * valueToPixelMatrix.a
        }

        let entries = axis.entries

        for i in entries.indices
        {
            let px = isCenteringEnabled ? CGFloat(axis.centeredEntries[i]) : CGFloat(entries[i])
            position = CGPoint(x: px, y: 0).applying(valueToPixelMatrix)

            guard viewPortHandler.isInBoundsX(position.x) else { continue }

            let label = axis.valueFormatter?.stringForValue(axis.entries[i], axis: axis) ?? ""
            let labelns = label as NSString

            if axis.isAvoidFirstLastClippingEnabled {
                if i == axis.entryCount - 1 && axis.entryCount > 1 {
                    let width = labelns.boundingRect(with: labelMaxSize, options: .usesLineFragmentOrigin, attributes: labelAttrs, context: nil).size.width
                    if width > viewPortHandler.offsetRight * 2.0 && position.x + width > viewPortHandler.chartWidth {
                        position.x -= width / 2.0
                    }
                } else if i == 0 {
                    let width = labelns.boundingRect(with: labelMaxSize, options: .usesLineFragmentOrigin, attributes: labelAttrs, context: nil).size.width
                    position.x += width / 2.0
                }
            }

            drawLabel(context: context, formattedLabel: label, x: position.x, y: pos,
                      attributes: labelAttrs, constrainedTo: labelMaxSize,
                      anchor: anchor, angleRadians: labelRotationAngleRadians)
        }
    }

    /// Draws x-axis labels with optional player image overlays from barDataSet entries.
    open func drawLabels(context: CGContext, pos: CGFloat, anchor: CGPoint, barDataSet: BarChartDataSetProtocol?)
    {
        guard let transformer = self.transformer else { return }

        let paraStyle = ParagraphStyle.default.mutableCopy() as! MutableParagraphStyle
        paraStyle.alignment = .center

        let labelAttrs: [NSAttributedString.Key: Any] = [.font: axis.labelFont,
                                                         .foregroundColor: axis.labelTextColor,
                                                         .paragraphStyle: paraStyle]
        let labelRotationAngleRadians = axis.labelRotationAngle.DEG2RAD
        let isCenteringEnabled = axis.isCenterAxisLabelsEnabled
        let valueToPixelMatrix = transformer.valueToPixelMatrix

        var position = CGPoint.zero
        var labelMaxSize = CGSize.zero
        if axis.isWordWrapEnabled {
            labelMaxSize.width = axis.wordWrapWidthPercent * valueToPixelMatrix.a
        }

        let entries = axis.entries

        for i in entries.indices
        {
            let px = isCenteringEnabled ? CGFloat(axis.centeredEntries[i]) : CGFloat(entries[i])
            position = CGPoint(x: px, y: 0).applying(valueToPixelMatrix)

            guard viewPortHandler.isInBoundsX(position.x) else { continue }

            let label = axis.valueFormatter?.stringForValue(axis.entries[i], axis: axis) ?? ""
            let player = axis.valueFormatter?.imageForValue(axis.entries[i], axis: axis)
            let labelns = label as NSString

            if axis.isAvoidFirstLastClippingEnabled {
                if i == axis.entryCount - 1 && axis.entryCount > 1 {
                    let width = labelns.boundingRect(with: labelMaxSize, options: .usesLineFragmentOrigin, attributes: labelAttrs, context: nil).size.width
                    if width > viewPortHandler.offsetRight * 2.0 && position.x + width > viewPortHandler.chartWidth {
                        position.x -= width / 2.0
                    }
                } else if i == 0 {
                    let width = labelns.boundingRect(with: labelMaxSize, options: .usesLineFragmentOrigin, attributes: labelAttrs, context: nil).size.width
                    position.x += width / 2.0
                }
            }

            let imageWidth: CGFloat = 36
            let topOffset: CGFloat = 12.5
            let playerIndex = Int(entries[i])

            var offset: CGFloat = 0
            if playerIndex >= 0, let currentSet = barDataSet?.entryForIndex(playerIndex) as? BarChartDataEntry {
                offset = currentSet.textOffset
            }

            if let p = player {
                var isExtraIconActive = false
                var shouldUseText = false

                context.saveGState()
                if playerIndex >= 0, let currentSet = barDataSet?.entryForIndex(playerIndex) as? BarChartDataEntry {
                    if currentSet.shouldDisplayBatteryLow || currentSet.shouldDisplayThunders {
                        isExtraIconActive = true
                    }
                    shouldUseText = currentSet.shouldUseTextValue
                }
                if !isExtraIconActive { isExtraIconActive = p.isBenched }

                if shouldUseText {
                    drawLabel(context: context, formattedLabel: label,
                              x: position.x + offset, y: pos,
                              attributes: labelAttrs, constrainedTo: labelMaxSize,
                              anchor: anchor, angleRadians: labelRotationAngleRadians)
                } else {
                    var imageRect = CGRect(x: position.x - imageWidth/2,
                                          y: position.y + topOffset,
                                          width: imageWidth, height: imageWidth)
                    if let img = p.playerImage.circleWithGrayOnTop(displayGreyColor: isExtraIconActive) {
                        img.draw(in: imageRect)
                    }
                }
                context.restoreGState()

                if playerIndex >= 0, let currentSet = barDataSet?.entryForIndex(playerIndex) as? BarChartDataEntry {
                    context.saveGState()
                    let imageRect = CGRect(x: position.x - imageWidth/2,
                                          y: position.y + topOffset,
                                          width: imageWidth, height: imageWidth)
                    let stateImgSize = imageRect.size.height * 0.45
                    let iconRect = CGRect(x: imageRect.origin.x,
                                         y: imageRect.maxY - stateImgSize,
                                         width: stateImgSize, height: stateImgSize)

                    if currentSet.shouldDisplayThunders {
                        UIImage(named: "red_range")?.draw(in: iconRect)
                    } else if currentSet.shouldDisplayBatteryLow {
                        UIImage(named: "batteryLow")?.draw(in: iconRect)
                    }
                    context.restoreGState()
                }
            } else {
                drawLabel(context: context, formattedLabel: label,
                          x: position.x + offset, y: pos,
                          attributes: labelAttrs, constrainedTo: labelMaxSize,
                          anchor: anchor, angleRadians: labelRotationAngleRadians)
            }
        }
    }

    @objc open func drawLabel(
        context: CGContext,
        formattedLabel: String,
        x: CGFloat,
        y: CGFloat,
        attributes: [NSAttributedString.Key: Any],
        constrainedTo size: CGSize,
        anchor: CGPoint,
        angleRadians: CGFloat)
    {
        context.drawMultilineText(formattedLabel,
                                  at: CGPoint(x: x, y: y),
                                  constrainedTo: size,
                                  anchor: anchor,
                                  angleRadians: angleRadians,
                                  attributes: attributes)
    }

    open func renderGridLines(context: CGContext)
    {
        guard
            let transformer = self.transformer,
            axis.isEnabled,
            axis.isDrawGridLinesEnabled
            else { return }

        context.saveGState()
        defer { context.restoreGState() }

        context.clip(to: self.gridClippingRect)
        context.setShouldAntialias(axis.gridAntialiasEnabled)
        context.setStrokeColor(axis.gridColor.cgColor)
        context.setLineWidth(axis.gridLineWidth)
        context.setLineCap(axis.gridLineCap)

        if axis.gridLineDashLengths != nil {
            context.setLineDash(phase: axis.gridLineDashPhase, lengths: axis.gridLineDashLengths)
        } else {
            context.setLineDash(phase: 0.0, lengths: [])
        }

        let valueToPixelMatrix = transformer.valueToPixelMatrix
        var position = CGPoint.zero

        for entry in axis.entries
        {
            position.x = CGFloat(entry)
            position.y = CGFloat(entry)
            position = position.applying(valueToPixelMatrix)
            drawGridLine(context: context, x: position.x, y: position.y)
        }
    }

    @objc open var gridClippingRect: CGRect
    {
        var contentRect = viewPortHandler.contentRect
        let dx = self.axis.gridLineWidth
        contentRect.origin.x -= dx / 2.0
        contentRect.size.width += dx
        return contentRect
    }

    @objc open func drawGridLine(context: CGContext, x: CGFloat, y: CGFloat)
    {
        guard x >= viewPortHandler.offsetLeft && x <= viewPortHandler.chartWidth else { return }
        context.beginPath()
        context.move(to: CGPoint(x: x, y: viewPortHandler.contentTop))
        context.addLine(to: CGPoint(x: x, y: viewPortHandler.contentBottom))
        context.strokePath()
    }

    open func renderLimitLines(context: CGContext)
    {
        guard let transformer = self.transformer, !axis.limitLines.isEmpty else { return }

        let trans = transformer.valueToPixelMatrix
        var position = CGPoint.zero

        for l in axis.limitLines where l.isEnabled
        {
            context.saveGState()
            defer { context.restoreGState() }

            var clippingRect = viewPortHandler.contentRect
            clippingRect.origin.x -= l.lineWidth / 2.0
            clippingRect.size.width += l.lineWidth
            context.clip(to: clippingRect)

            position.x = CGFloat(l.limit)
            position.y = 0.0
            position = position.applying(trans)

            renderLimitLineLine(context: context, limitLine: l, position: position)
            renderLimitLineLabel(context: context, limitLine: l, position: position, yOffset: 2.0 + l.yOffset)
        }
    }

    @objc open func renderLimitLineLine(context: CGContext, limitLine: ChartLimitLine, position: CGPoint)
    {
        context.beginPath()
        context.move(to: CGPoint(x: position.x, y: viewPortHandler.contentTop))
        context.addLine(to: CGPoint(x: position.x, y: viewPortHandler.contentBottom))

        context.setStrokeColor(limitLine.lineColor.cgColor)
        context.setLineWidth(limitLine.lineWidth)
        if limitLine.lineDashLengths != nil {
            context.setLineDash(phase: limitLine.lineDashPhase, lengths: limitLine.lineDashLengths!)
        } else {
            context.setLineDash(phase: 0.0, lengths: [])
        }
        context.strokePath()
    }

    @objc open func renderLimitLineLabel(context: CGContext, limitLine: ChartLimitLine, position: CGPoint, yOffset: CGFloat)
    {
        let label = limitLine.label
        guard limitLine.drawLabelEnabled, !label.isEmpty else { return }

        let labelLineSize = label.size(withAttributes: [.font: limitLine.valueFont])
        let labelLineRotatedSize = labelLineSize.rotatedBy(degrees: limitLine.labelRotationAngle)
        let labelLineRotatedWidth = labelLineRotatedSize.width
        let labelLineRotatedHeight = labelLineRotatedSize.height
        let xOffset: CGFloat = limitLine.lineWidth + limitLine.xOffset
        let labelRotationAngleRadians = limitLine.labelRotationAngle.DEG2RAD
        let anchor = CGPoint(x: 0.0, y: 0.0)

        let attributes: [NSAttributedString.Key: Any] = [.font: limitLine.valueFont, .foregroundColor: limitLine.valueTextColor]

        let point: CGPoint
        switch limitLine.labelPosition {
        case .rightTop:
            point = CGPoint(x: position.x + xOffset, y: viewPortHandler.contentTop + yOffset)
        case .rightBottom:
            point = CGPoint(x: position.x + xOffset, y: viewPortHandler.contentBottom - labelLineRotatedHeight - yOffset)
        case .leftTop:
            point = CGPoint(x: position.x - labelLineRotatedWidth - xOffset, y: viewPortHandler.contentTop + yOffset)
        case .leftBottom:
            point = CGPoint(x: position.x - labelLineRotatedWidth - xOffset, y: viewPortHandler.contentBottom - labelLineRotatedHeight - yOffset)
        }

        context.drawText(label, at: point, anchor: anchor, angleRadians: labelRotationAngleRadians, attributes: attributes)
    }
}

extension UIImage {
    var circle: UIImage? {
        let square = CGSize(width: min(size.width, size.height), height: min(size.width, size.height))
        let imageView = UIImageView(frame: CGRect(origin: .zero, size: square))
        imageView.contentMode = .scaleAspectFill
        imageView.image = self
        imageView.layer.cornerRadius = square.width / 2
        imageView.layer.masksToBounds = true
        UIGraphicsBeginImageContextWithOptions(imageView.bounds.size, false, scale)
        guard let ctx = UIGraphicsGetCurrentContext() else { return nil }
        imageView.layer.render(in: ctx)
        let result = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return result
    }

    func circleWithGrayOnTop(displayGreyColor: Bool) -> UIImage? {
        let square = CGSize(width: min(size.width, size.height), height: min(size.width, size.height))
        let imageView = UIImageView(frame: CGRect(origin: .zero, size: square))
        if displayGreyColor {
            let overlay = CALayer()
            overlay.backgroundColor = UIColor.black.withAlphaComponent(0.5).cgColor
            overlay.frame = imageView.bounds
            imageView.layer.addSublayer(overlay)
        }
        imageView.contentMode = .scaleAspectFill
        imageView.image = self
        imageView.layer.cornerRadius = square.width / 2
        imageView.layer.masksToBounds = true
        guard imageView.bounds.size != .zero else { return nil }
        UIGraphicsBeginImageContextWithOptions(imageView.bounds.size, false, scale)
        guard let ctx = UIGraphicsGetCurrentContext() else { return nil }
        imageView.layer.render(in: ctx)
        let result = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return result
    }
}

extension UIView {
    func setBackgroundShadow() {
        self.layer.shadowColor = UIColor(white: 0.0, alpha: 0.65).cgColor
        self.layer.masksToBounds = false
        self.layer.shadowOpacity = 1.0
        self.layer.shadowRadius = 3.0
        self.layer.shadowOffset = CGSize(width: 0.0, height: 3.0)
    }
}
