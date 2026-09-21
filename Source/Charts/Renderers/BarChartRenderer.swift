//
//  BarChartRenderer.swift
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

open class MetricThresholdsConfigurations {
    let betweenBoxSpace = 5
    let boxBorder: CGFloat = 1

    func drawThresholdBox(context: CGContext, point: CGPoint, currentTextSize: CGSize, thresholdColor: UIColor, boxOpacity: Double = 0.3) {
        let boxOffset: CGFloat = 5
        let backgroundRect = CGRect(x: point.x - currentTextSize.width/2 - boxOffset,
                                    y: point.y,
                                    width: currentTextSize.width + boxOffset*2,
                                    height: currentTextSize.height)
        let borderPath = UIBezierPath(roundedRect: backgroundRect, cornerRadius: 4)

        context.saveGState()
        context.addPath(borderPath.cgPath)
        context.setFillColor(thresholdColor.withAlphaComponent(boxOpacity).cgColor)
        context.closePath()
        context.fillPath()
        context.restoreGState()

        context.saveGState()
        context.addPath(borderPath.cgPath)
        context.setStrokeColor(thresholdColor.cgColor)
        context.setLineWidth(boxBorder)
        context.closePath()
        context.strokePath()
        context.restoreGState()
    }

    func getTextSize(stringToUse: String, font: NSUIFont, color: NSUIColor) -> CGSize {
        return stringToUse.size(withAttributes: [NSAttributedString.Key.font: font,
                                                 NSAttributedString.Key.foregroundColor: color])
    }
}

open class BarChartRenderer: BarLineScatterCandleBubbleRenderer
{
    /// A nested array of elements ordered logically (not in visual/drawing order) for VoiceOver.
    internal lazy var accessibilityOrderedElements: [[NSUIAccessibilityElement]] = accessibilityCreateEmptyOrderedElements()

    private typealias Buffer = [CGRect]

    @objc open weak var dataProvider: BarChartDataProvider?

    @objc public init(dataProvider: BarChartDataProvider, animator: Animator, viewPortHandler: ViewPortHandler)
    {
        super.init(animator: animator, viewPortHandler: viewPortHandler)
        self.dataProvider = dataProvider
    }

    private let bottomLabelOffset: CGFloat = 25

    // [CGRect] per dataset
    private var _buffers = [Buffer]()

    open override func initBuffers()
    {
        guard let barData = dataProvider?.barData else { return _buffers.removeAll() }

        if _buffers.count != barData.count
        {
            while _buffers.count < barData.count { _buffers.append(Buffer()) }
            while _buffers.count > barData.count { _buffers.removeLast() }
        }

        _buffers = zip(_buffers, barData).map { buffer, set -> Buffer in
            let set = set as! BarChartDataSetProtocol
            let size = set.entryCount * (set.isStacked ? set.stackSize : 1)
            return buffer.count == size ? buffer : Buffer(repeating: .zero, count: size)
        }
    }

    private func prepareBuffer(dataSet: BarChartDataSetProtocol, index: Int)
    {
        guard
            let dataProvider = dataProvider,
            let barData = dataProvider.barData
            else { return }

        let barWidthHalf = CGFloat(barData.barWidth / 2.0)
        var bufferIndex = 0
        let containsStacks = dataSet.isStacked
        let isInverted = dataProvider.isInverted(axis: dataSet.axisDependency)
        let phaseY = CGFloat(animator.phaseY)

        for i in (0..<dataSet.entryCount).clamped(to: 0..<Int(ceil(Double(dataSet.entryCount) * animator.phaseX)))
        {
            guard let e = dataSet.entryForIndex(i) as? BarChartDataEntry else { continue }

            let x = CGFloat(e.x)
            let left = x - barWidthHalf
            let right = x + barWidthHalf
            var y = e.y

            if containsStacks, let vals = e.yValues
            {
                var posY = 0.0
                var negY = -e.negativeSum
                var yStart = 0.0

                for k in 0..<vals.count
                {
                    var val: Double
                    if k > 0 && (vals[k] * 1.3 - vals[k-1]) >= 0 {
                        val = (vals[k] * 1.3) - vals[k-1]
                    } else if k > 0 {
                        val = 0
                    } else {
                        val = vals[k]
                    }

                    let value = barData.useStatSportsChart ? val : vals[k]

                    if value >= 0.0 { y = posY; yStart = posY + value; posY = yStart }
                    else { y = negY; yStart = negY + abs(value); negY += abs(value) }

                    var top = isInverted
                        ? (y <= yStart ? CGFloat(y) : CGFloat(yStart))
                        : (y >= yStart ? CGFloat(y) : CGFloat(yStart))
                    var bottom = isInverted
                        ? (y >= yStart ? CGFloat(y) : CGFloat(yStart))
                        : (y <= yStart ? CGFloat(y) : CGFloat(yStart))

                    top *= phaseY
                    bottom *= phaseY

                    _buffers[index][bufferIndex] = CGRect(x: left, y: top, width: right - left, height: bottom - top)
                    bufferIndex += 1
                }
            }
            else
            {
                var top = isInverted
                    ? (y <= 0.0 ? CGFloat(y) : 0)
                    : (y >= 0.0 ? CGFloat(y) : 0)
                var bottom = isInverted
                    ? (y >= 0.0 ? CGFloat(y) : 0)
                    : (y <= 0.0 ? CGFloat(y) : 0)

                if top > 0 { top *= phaseY } else { bottom *= phaseY }

                _buffers[index][bufferIndex] = CGRect(x: left, y: top, width: right - left, height: bottom - top)
                bufferIndex += 1
            }
        }
    }

    open override func drawData(context: CGContext)
    {
        guard
            let dataProvider = dataProvider,
            let barData = dataProvider.barData
            else { return }

        accessibleChartElements.removeAll()
        accessibilityOrderedElements = accessibilityCreateEmptyOrderedElements()

        if let chart = dataProvider as? BarChartView {
            let element = createAccessibleHeader(usingChart: chart,
                                                 andData: barData,
                                                 withDefaultDescription: "Bar Chart")
            accessibleChartElements.append(element)

            // Pass first visible dataset to XAxisRenderer so renderAxisLabels
            // can draw player images instead of plain text labels.
            if let xRenderer = chart.xAxisRenderer as? XAxisRenderer {
                xRenderer.barDataSet = barData.first(where: { $0.isVisible }) as? BarChartDataSetProtocol
            }
        }

        for i in barData.indices
        {
            guard let set = barData[i] as? BarChartDataSetProtocol else {
                fatalError("Datasets for BarChartRenderer must conform to IBarChartDataset")
            }
            guard set.isVisible else { continue }
            drawDataSet(context: context, dataSet: set, index: i)
        }

        accessibleChartElements.append(contentsOf: accessibilityOrderedElements.flatMap { $0 })
        accessibilityPostLayoutChangedNotification()
    }

    private var _barShadowRectBuffer: CGRect = CGRect()

    @objc open func drawDataSet(context: CGContext, dataSet: BarChartDataSetProtocol, index: Int)
    {
        guard let dataProvider = dataProvider else { return }

        let isThresholdEnabled = dataProvider.barData?.isThresholdEnabled ?? false
        let trans = dataProvider.getTransformer(forAxis: dataSet.axisDependency)

        prepareBuffer(dataSet: dataSet, index: index)
        trans.rectValuesToPixel(&_buffers[index])

        context.saveGState()

        guard let currentBarData = dataProvider.barData else {
            context.restoreGState()
            return
        }

        // Collect yValues arrays for threshold calculations in drawSingleBarData
        var values = [[Double]]()
        let phaseXCount = Int(ceil(Double(dataSet.entryCount) * animator.phaseX))
        for i in 0..<min(phaseXCount, dataSet.entryCount)
        {
            guard let e = dataSet.entryForIndex(i) as? BarChartDataEntry else { continue }
            values.append(e.yValues ?? [])
        }

        // Draw bar shadows (threshold mode only)
        if dataProvider.isDrawBarShadowEnabled && isThresholdEnabled
        {
            let barWidth = currentBarData.barWidth
            let barWidthHalf = barWidth / 2.0
            for i in 0..<min(phaseXCount, dataSet.entryCount)
            {
                guard let e = dataSet.entryForIndex(i) as? BarChartDataEntry else { continue }
                _barShadowRectBuffer.origin.x = CGFloat(e.x - barWidthHalf)
                _barShadowRectBuffer.size.width = CGFloat(barWidth)
                trans.rectValueToPixel(&_barShadowRectBuffer)

                guard viewPortHandler.isInBoundsLeft(_barShadowRectBuffer.origin.x + _barShadowRectBuffer.size.width) else { continue }
                guard viewPortHandler.isInBoundsRight(_barShadowRectBuffer.origin.x) else { break }

                _barShadowRectBuffer.origin.y = viewPortHandler.contentTop
                _barShadowRectBuffer.size.height = viewPortHandler.contentHeight + viewPortHandler.offsetBottom
                context.setFillColor(dataSet.barShadowColor.cgColor)
                context.fill(_barShadowRectBuffer)
            }
        }

        if currentBarData.shouldUseStackedBarUI {
            drawStackedBarData(context: context,
                               dataProvider: dataProvider,
                               buffer: _buffers[index],
                               viewPortHandler: viewPortHandler,
                               dataSet: dataSet)
        } else {
            drawSingleBarData(context: context,
                              viewPortHandler: viewPortHandler,
                              values: values,
                              currentBarData: currentBarData,
                              isThresholdEnabled: isThresholdEnabled,
                              trans: trans,
                              dataSet: dataSet,
                              index: index)
        }

        context.restoreGState()

        // Accessibility pass
        let buffer = _buffers[index]
        let stackSize = dataSet.isStacked ? dataSet.stackSize : 1
        for j in buffer.indices
        {
            let barRect = buffer[j]
            guard viewPortHandler.isInBoundsLeft(barRect.origin.x + barRect.size.width),
                  viewPortHandler.isInBoundsRight(barRect.origin.x) else { continue }
            if let chart = dataProvider as? BarChartView
            {
                let element = createAccessibleElement(
                    withIndex: j,
                    container: chart,
                    dataSet: dataSet,
                    dataSetIndex: index,
                    stackSize: stackSize
                ) { element in element.accessibilityFrame = barRect }
                accessibilityOrderedElements[j/stackSize].append(element)
            }
        }
    }

    private func drawSingleBarData(context: CGContext, viewPortHandler: ViewPortHandler, values: [[Double]], currentBarData: BarChartData, isThresholdEnabled: Bool, trans: Transformer, dataSet: BarChartDataSetProtocol, index: Int)
    {
        let buffer = _buffers[index]
        for j in stride(from: 0, to: buffer.count, by: 2)
        {
            let barRect = buffer[j]
            guard viewPortHandler.isInBoundsLeft(barRect.origin.x + barRect.size.width) else { continue }
            guard viewPortHandler.isInBoundsRight(barRect.origin.x) else { break }

            let defaultColor = dataSet.color(atIndex: 0)
            var startColor = defaultColor
            var endColor = defaultColor

            let valueIndex = j == 0 ? 0 : j / 2
            if isThresholdEnabled && valueIndex < values.count && values[valueIndex].count >= 2 {
                let threshold = values[valueIndex][1]
                let percentage = threshold > 0 ? values[valueIndex][0] / threshold : 0
                let zones = currentBarData.thresholdZones
                let colors = currentBarData.thresholdZonesColors
                if zones.count >= 3 && colors.count >= 4 {
                    if percentage >= 0 && percentage <= zones[1] {
                        startColor = colors[0]; endColor = colors[0]
                    } else if percentage > zones[1] && percentage <= zones[2] {
                        startColor = colors[1]; endColor = colors[1]
                    } else if zones.count >= 4 && percentage > zones[2] && percentage <= zones[3] {
                        startColor = colors[2]; endColor = colors[2]
                    } else {
                        startColor = colors[3]; endColor = colors[3]
                    }
                }
            }

            let gradColors = [endColor.cgColor, startColor.cgColor]
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            let colorLocations: [CGFloat] = [0.5, 1.0]
            let gradient = CGGradient(colorsSpace: colorSpace, colors: gradColors as CFArray, locations: colorLocations)
            let opts: CGGradientDrawingOptions = [.drawsAfterEndLocation]

            context.saveGState()
            var cr = barRect.size; cr.width = 0; cr.height = 0
            let clipPath = UIBezierPath(roundedRect: barRect, byRoundingCorners: [.topLeft, .topRight], cornerRadii: cr)
            clipPath.addClip()
            context.drawLinearGradient(gradient!, start: .zero, end: CGPoint(x: 0, y: barRect.maxY), options: opts)
            context.restoreGState()

            // Threshold delimiter lines
            if isThresholdEnabled && valueIndex < values.count && values[valueIndex].count >= 2 {
                context.saveGState()
                let thresholdVal = values[valueIndex][1]
                for i in 0...2 {
                    let zones = currentBarData.thresholdZones
                    let multiplier: Double
                    if zones.count >= 4 {
                        multiplier = i == 0 ? zones[3] : (i == 1 ? zones[2] : zones[1])
                    } else if zones.count == 3 {
                        multiplier = i == 0 ? zones[2] : (i == 1 ? zones[1] : zones[0])
                    } else {
                        multiplier = i == 0 ? 1.25 : (i == 1 ? 1.1 : 0.75)
                    }
                    var br = CGRect(x: 10, y: thresholdVal * multiplier, width: 100, height: thresholdVal * 0.02)
                    trans.rectValueToPixel(&br)
                    br.origin.x = barRect.origin.x
                    br.size.width = barRect.size.width
                    br.size.height = 2.0
                    context.setFillColor(currentBarData.delimiterColor.cgColor)
                    context.fill(br)
                }
                context.restoreGState()
            }

            // Bottom value background pill
            if let e = dataSet.entryForIndex(index) as? BarChartDataEntry, e.drawBottomValue {
                context.saveGState()
                let yPos = viewPortHandler.contentBottom - bottomLabelOffset
                let bgWidth: CGFloat = barRect.size.width + 12
                let bgHeight: CGFloat = 20
                let xPos: CGFloat
                if bgWidth < barRect.size.width {
                    xPos = barRect.origin.x + barRect.size.width/2 - bgWidth/2
                } else {
                    xPos = barRect.origin.x - abs(bgWidth - barRect.size.width)/2
                }
                let rectangle = CGRect(x: xPos, y: yPos, width: bgWidth, height: bgHeight)
                context.addPath(UIBezierPath(roundedRect: rectangle, cornerRadius: 4).cgPath)
                context.setFillColor((dataSet as? BarChartDataSet)?.bottomValueBackgroundColor.cgColor ?? UIColor.white.cgColor)
                context.closePath()
                context.fillPath()
                context.restoreGState()
            }
        }
    }

    private func drawStackedBarData(context: CGContext, dataProvider: BarChartDataProvider, buffer: Buffer, viewPortHandler: ViewPortHandler, dataSet: BarChartDataSetProtocol)
    {
        let shouldUseStackedUI = dataProvider.barData?.shouldUseStackedBarUI ?? false
        var indexStartSkipping = 3
        if let idx = dataProvider.barData?.indexStartSkipping { indexStartSkipping = idx }
        let indexStopSkipping = 4
        var currentStep = 0

        for j in buffer.indices
        {
            let barRect = buffer[j]
            guard viewPortHandler.isInBoundsLeft(barRect.origin.x + barRect.size.width) else { continue }
            guard viewPortHandler.isInBoundsRight(barRect.origin.x) else { break }

            currentStep += 1
            if shouldUseStackedUI && currentStep >= indexStartSkipping {
                if currentStep >= indexStopSkipping { currentStep = 0 }
                continue
            }

            let newColors = dataSet.colors
            let barColor = newColors.count >= 2 ? (currentStep == 1 ? newColors[0] : newColors[1]) : dataSet.color(atIndex: 0)
            let gradColors = [barColor.cgColor, barColor.cgColor]
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            let colorLocations: [CGFloat] = [0.5, 1.0]
            let gradient = CGGradient(colorsSpace: colorSpace, colors: gradColors as CFArray, locations: colorLocations)
            let opts: CGGradientDrawingOptions = [.drawsAfterEndLocation]

            context.saveGState()
            if currentStep == indexStartSkipping - 1 {
                var cr = barRect.size; cr.width = 0; cr.height = 0
                let path2 = UIBezierPath(roundedRect: barRect, byRoundingCorners: [.topLeft, .topRight], cornerRadii: cr)
                path2.addClip()
                context.drawLinearGradient(gradient!, start: .zero, end: CGPoint(x: 0, y: barRect.maxY), options: opts)
            } else {
                let clearLine: CGFloat = 2.0
                var cr = barRect.size; cr.width = 0; cr.height = 0
                let newRect = CGRect(x: barRect.minX, y: barRect.minY + clearLine, width: barRect.width, height: barRect.height - clearLine)
                let path2 = UIBezierPath(roundedRect: newRect, byRoundingCorners: [.topLeft, .topRight], cornerRadii: cr)
                path2.addClip()
                context.drawLinearGradient(gradient!, start: .zero, end: CGPoint(x: 0, y: barRect.maxY), options: opts)
            }
            context.restoreGState()
        }
    }

    open func prepareBarHighlight(
        x: Double,
        y1: Double,
        y2: Double,
        barWidthHalf: Double,
        trans: Transformer,
        rect: inout CGRect)
    {
        rect.origin.x = CGFloat(x - barWidthHalf)
        rect.origin.y = CGFloat(y1)
        rect.size.width = CGFloat(barWidthHalf * 2)
        rect.size.height = CGFloat(y2 - y1)
        trans.rectValueToPixel(&rect, phaseY: animator.phaseY)
    }

    open override func drawValues(context: CGContext)
    {
        guard isDrawingValuesAllowed(dataProvider: dataProvider),
              let dataProvider = dataProvider,
              let barData = dataProvider.barData
              else { return }

        let valueOffsetPlus: CGFloat = 4.5
        var posOffset: CGFloat
        var negOffset: CGFloat

        for dataSetIndex in barData.indices
        {
            guard
                let dataSet = barData[dataSetIndex] as? BarChartDataSetProtocol,
                shouldDrawValues(forDataSet: dataSet)
                else { continue }

            let isInverted = dataProvider.isInverted(axis: dataSet.axisDependency)
            let valueFont = dataSet.valueFont
            let valueTextHeight = valueFont.lineHeight
            posOffset = -(valueTextHeight + valueOffsetPlus)
            negOffset = valueOffsetPlus

            if isInverted {
                posOffset = -posOffset - valueTextHeight
                negOffset = -negOffset - valueTextHeight
            }

            let buffer = _buffers[dataSetIndex]
            let formatter = dataSet.valueFormatter
            let trans = dataProvider.getTransformer(forAxis: dataSet.axisDependency)
            let phaseY = animator.phaseY

            if !dataSet.isStacked
            {
                for j in 0..<Int(ceil(Double(dataSet.entryCount) * animator.phaseX))
                {
                    guard let e = dataSet.entryForIndex(j) as? BarChartDataEntry else { continue }
                    let rect = buffer[j]
                    let x = rect.origin.x + rect.size.width / 2.0

                    guard viewPortHandler.isInBoundsRight(x) else { break }
                    guard viewPortHandler.isInBoundsY(rect.origin.y),
                          viewPortHandler.isInBoundsLeft(x) else { continue }

                    if dataSet.isDrawValuesEnabled {
                        drawValue(
                            context: context,
                            value: formatter.stringForValue(e.y, entry: e, dataSetIndex: dataSetIndex, viewPortHandler: viewPortHandler),
                            xPos: x,
                            yPos: e.y >= 0.0 ? (rect.origin.y + posOffset) : (rect.origin.y + rect.size.height + negOffset),
                            font: valueFont,
                            align: .center,
                            color: dataSet.valueTextColorAt(j),
                            anchor: CGPoint(x: 0.5, y: 0.5),
                            angleRadians: 0.0)
                    }
                }
            }
            else
            {
                var bufferIndex = 0
                for index in 0..<Int(ceil(Double(dataSet.entryCount) * animator.phaseX))
                {
                    guard let e = dataSet.entryForIndex(index) as? BarChartDataEntry else { continue }
                    let vals = e.yValues
                    let rect = buffer[bufferIndex]
                    let x = rect.origin.x + rect.size.width / 2.0

                    if vals == nil
                    {
                        guard viewPortHandler.isInBoundsRight(x) else { break }
                        guard viewPortHandler.isInBoundsY(rect.origin.y),
                              viewPortHandler.isInBoundsLeft(x) else { continue }
                        if dataSet.isDrawValuesEnabled {
                            drawValue(
                                context: context,
                                value: formatter.stringForValue(e.y, entry: e, dataSetIndex: dataSetIndex, viewPortHandler: viewPortHandler),
                                xPos: x,
                                yPos: rect.origin.y + (e.y >= 0 ? posOffset : negOffset),
                                font: valueFont,
                                align: .center,
                                color: dataSet.valueTextColorAt(index),
                                anchor: CGPoint(x: 0.5, y: 0.5),
                                angleRadians: 0.0)
                        }
                    }
                    else
                    {
                        let vals = vals!
                        var transformed = [CGPoint]()
                        var posY = 0.0
                        var negY = -e.negativeSum

                        for k in 0..<vals.count
                        {
                            let v = vals[k]
                            let y: Double
                            if v >= 0.0 { posY += v; y = posY } else { y = negY; negY -= v }
                            transformed.append(CGPoint(x: 0.0, y: CGFloat(y * phaseY)))
                        }
                        trans.pointValuesToPixel(&transformed)

                        for k in 0..<transformed.count
                        {
                            var val: Double
                            if k > 0 && (vals[k] - vals[k-1]) > 0 { val = vals[k] - vals[k-1] }
                            else if k > 0 { val = 0 }
                            else { val = vals[k] }

                            var value = e.useStatSportsChart ? val : vals[k]
                            let y = transformed[k].y + (value >= 0 ? posOffset : negOffset)

                            guard viewPortHandler.isInBoundsRight(x) else { break }

                            if !barData.shouldUseStackedBarUI {
                                guard viewPortHandler.isInBoundsY(y),
                                      viewPortHandler.isInBoundsLeft(x) else { continue }
                            }

                            var stringToDisplay = getStringToShow(k: k, barData: barData, value: &value, e: e, decimals: barData.decimals)
                            if let secondDigits = barData.decimalsSecondValuesRow, k >= 1, barData.shouldUseStackedBarUI {
                                stringToDisplay = getStringToShow(k: k, barData: barData, value: &value, e: e, decimals: secondDigits)
                            }

                            if !barData.shouldUseStackedBarUI {
                                if e.drawTopSecondValue && dataSet.isDrawValuesEnabled {
                                    drawValue(context: context,
                                              value: formatter.stringFor(stringToDisplay, entry: e, dataSetIndex: dataSetIndex, viewPortHandler: viewPortHandler),
                                              xPos: x, yPos: viewPortHandler.contentTop,
                                              font: valueFont, align: .center,
                                              color: dataSet.valueTextColorAt(index),
                                              anchor: CGPoint(x: 0.5, y: 0.5), angleRadians: 0.0)
                                }
                                if e.drawBottomValue {
                                    let bottomColor = (barData[safe: 0] as? BarChartDataSet)?.bottomValueTextColor ?? UIColor.white
                                    drawValue(context: context, value: stringToDisplay,
                                              xPos: x, yPos: viewPortHandler.contentBottom - bottomLabelOffset,
                                              font: valueFont, align: .center, color: bottomColor,
                                              anchor: CGPoint(x: 0.5, y: 0.5), angleRadians: 0.0)
                                }
                            } else {
                                let thresholdConfig = MetricThresholdsConfigurations()
                                let stringToUse = "\(stringToDisplay)\(barData.prefixStringToValues)"
                                let currentTextSize = thresholdConfig.getTextSize(stringToUse: stringToUse, font: valueFont, color: dataSet.valueTextColorAt(index))
                                let betweenBoxSpace = thresholdConfig.betweenBoxSpace
                                let boxBorder: CGFloat = thresholdConfig.boxBorder
                                var finalYPos = viewPortHandler.contentTop + boxBorder
                                if k > 0 {
                                    finalYPos = viewPortHandler.contentTop + currentTextSize.height * CGFloat(k) + CGFloat(betweenBoxSpace * k)
                                }
                                if k >= 2 { continue }

                                var percentage = 0.0
                                if vals.count >= k + 3 { percentage = vals[k] / vals[k + 2] }

                                let thresholdColor = getThresholdColor(barData: barData, percentage: percentage)
                                if barData.shouldDrawThresholdValueBoxes {
                                    thresholdConfig.drawThresholdBox(context: context, point: CGPoint(x: x, y: finalYPos), currentTextSize: currentTextSize, thresholdColor: thresholdColor)
                                }
                                if dataSet.isDrawValuesEnabled {
                                    drawValue(context: context, value: stringToDisplay,
                                              xPos: x, yPos: finalYPos,
                                              font: valueFont, align: .center,
                                              color: dataSet.valueTextColorAt(index),
                                              anchor: CGPoint(x: 0.5, y: 0.5), angleRadians: 0.0)
                                }
                            }
                        }
                    }
                    bufferIndex += vals?.count ?? 1
                }
            }
        }
    }

    private func getThresholdColor(barData: BarChartData, percentage: Double) -> UIColor
    {
        let zones = barData.thresholdZones
        let colors = barData.thresholdZonesColors
        guard zones.count >= 3 && colors.count >= 4 else {
            return barData[safe: 0]?.colors.first ?? .clear
        }
        if percentage >= 0 && percentage <= zones[1] { return colors[0] }
        if percentage > zones[1] && percentage <= zones[2] { return colors[1] }
        if zones.count >= 4 && percentage > zones[2] && percentage <= zones[3] { return colors[2] }
        return colors[3]
    }

    private func getStringToShow(k: Int, barData: BarChartData, value: inout Double, e: BarChartDataEntry, decimals: Int) -> String
    {
        var stringToDisplay = ""
        if k > 0 && barData.useStatSportsChart {
            value = 0
        } else {
            switch decimals {
            case 0:   stringToDisplay = String(Int(round(value)))
            case 1:   stringToDisplay = String(format: "%.1f", value.roundTo1f)
            case 2:   stringToDisplay = String(format: "%.2f", value.roundTo2f)
            case 3:   stringToDisplay = String(format: "%.3f", value.roundTo3f)
            case 100: stringToDisplay = value != 0.0 ? value.timeInRedZoneString() : "00:00"
            default:  stringToDisplay = String(round(value))
            }
        }

        if value == 0 && !e.useStatSportsChart {
            if k == 0 && barData.decimals == 100 {
                stringToDisplay = "00:00"
            } else if k == 1 {
                stringToDisplay = barData.shouldUseStackedBarUI ? String(format: "%.\(decimals)f", 0) : ""
            }
        }
        return stringToDisplay
    }

    @objc open func drawValue(context: CGContext, value: String, xPos: CGFloat, yPos: CGFloat, font: NSUIFont, align: TextAlignment, color: NSUIColor, anchor: CGPoint, angleRadians: CGFloat)
    {
        if angleRadians == 0.0 {
            context.drawText(value, at: CGPoint(x: xPos, y: yPos), align: align, attributes: [.font: font, .foregroundColor: color])
        } else {
            context.drawText(value, at: CGPoint(x: xPos, y: yPos), align: align, anchor: anchor, angleRadians: angleRadians, attributes: [.font: font, .foregroundColor: color])
        }
    }

    open override func drawExtras(context: CGContext) { }

    open override func drawHighlighted(context: CGContext, indices: [Highlight])
    {
        guard
            let dataProvider = dataProvider,
            let barData = dataProvider.barData
            else { return }

        context.saveGState()
        defer { context.restoreGState() }
        var barRect = CGRect()

        for high in indices
        {
            guard
                let set = barData[safe: high.dataSetIndex] as? BarChartDataSetProtocol,
                set.isHighlightEnabled
                else { continue }

            if let e = set.entryForXValue(high.x, closestToY: high.y) as? BarChartDataEntry
            {
                guard isInBoundsX(entry: e, dataSet: set) else { continue }

                let trans = dataProvider.getTransformer(forAxis: set.axisDependency)
                context.setFillColor(set.highlightColor.cgColor)
                context.setAlpha(set.highlightAlpha)

                let isStack = high.stackIndex >= 0 && e.isStacked
                let y1: Double
                let y2: Double

                if isStack {
                    if dataProvider.isHighlightFullBarEnabled {
                        y1 = e.positiveSum; y2 = -e.negativeSum
                    } else {
                        let range = e.ranges?[high.stackIndex]
                        y1 = range?.from ?? 0.0; y2 = range?.to ?? 0.0
                    }
                } else {
                    y1 = e.y; y2 = 0.0
                }

                prepareBarHighlight(x: e.x, y1: y1, y2: y2, barWidthHalf: barData.barWidth / 2.0, trans: trans, rect: &barRect)
                setHighlightDrawPos(highlight: high, barRect: barRect)

                var roundedCorners = set.roundedCorners
                if e.y < 0 { roundedCorners = set.roundedCornersInverted }
                let bezierPath = UIBezierPath(roundedRect: barRect, byRoundingCorners: roundedCorners,
                                              cornerRadii: .init(width: set.cornerRadius, height: set.cornerRadius))
                context.addPath(bezierPath.cgPath)
                context.drawPath(using: .fill)
            }
        }
    }

    internal func setHighlightDrawPos(highlight high: Highlight, barRect: CGRect)
    {
        high.setDraw(x: barRect.midX, y: barRect.origin.y)
    }

    internal func accessibilityCreateEmptyOrderedElements() -> [[NSUIAccessibilityElement]]
    {
        guard let chart = dataProvider as? BarChartView else { return [] }
        let maxEntryCount = chart.data?.maxEntryCountSet?.entryCount ?? 0
        return Array(repeating: [NSUIAccessibilityElement](), count: maxEntryCount)
    }

    internal func createAccessibleElement(withIndex idx: Int,
                                          container: BarChartView,
                                          dataSet: BarChartDataSetProtocol,
                                          dataSetIndex: Int,
                                          stackSize: Int,
                                          modifier: (NSUIAccessibilityElement) -> ()) -> NSUIAccessibilityElement
    {
        let element = NSUIAccessibilityElement(accessibilityContainer: container)
        let xAxis = container.xAxis
        guard let e = dataSet.entryForIndex(idx/stackSize) as? BarChartDataEntry else { return element }
        guard let dataProvider = dataProvider else { return element }

        let label = xAxis.valueFormatter?.stringForValue(e.x, axis: xAxis) ?? "\(e.x)"
        var elementValueText = dataSet.valueFormatter.stringForValue(e.y, entry: e, dataSetIndex: dataSetIndex, viewPortHandler: viewPortHandler)

        if dataSet.isStacked, let vals = e.yValues
        {
            let labelCount = min(dataSet.colors.count, stackSize)
            let stackLabel: String?
            if !dataSet.stackLabels.isEmpty && labelCount > 0 {
                let labelIndex = idx % labelCount
                stackLabel = dataSet.stackLabels.indices.contains(labelIndex) ? dataSet.stackLabels[labelIndex] : nil
            } else {
                stackLabel = nil
            }
            let yValue = vals.isEmpty ? 0.0 : vals[idx % vals.count]
            elementValueText = dataSet.valueFormatter.stringForValue(yValue, entry: e, dataSetIndex: dataSetIndex, viewPortHandler: viewPortHandler)
            if let stackLabel = stackLabel {
                elementValueText = stackLabel + " \(elementValueText)"
            }
        }

        let doesContainMultiple = (dataProvider.barData?.dataSetCount ?? 0) > 1
        element.accessibilityLabel = "\(doesContainMultiple ? (dataSet.label ?? "") + ", " : "") \(label): \(elementValueText)"
        modifier(element)
        return element
    }
}

extension UIColor {
    var connectedColor: UIColor { return UIColor.hexStr(hexStr: "#00b600") }
    var disconnectedColor: UIColor { return UIColor.hexStr(hexStr: "#8a8a8a") }
    var lowBatteryColor: UIColor { return UIColor.hexStr(hexStr: "#ec1f27") }

    var connectedTextColor: UIColor { return UIColor.black }
    var disconnectedTextColor: UIColor { return UIColor.hexStr(hexStr: "#7E7E7E") }
    var lowBatteryTextColor: UIColor { return UIColor.hexStr(hexStr: "#F0898D") }

    var defaultBar: DefaultBar { return DefaultBar() }
    var optimumBar: OptimumBar { return OptimumBar() }
    var warningBar: WarningBar { return WarningBar() }
    var dangerBar: DangerBar { return DangerBar() }

    var thresholdBarColor: UIColor { return UIColor.hexStr(hexStr: "C5C6C6") }
    var selectedRow: UIColor { return UIColor.hexStr(hexStr: "00B17A") }
    var subCellColor: UIColor { return UIColor.hexStr(hexStr: "E4E4E4") }
    var settingsHeaderColor: UIColor { return UIColor.hexStr(hexStr: "EFEFF4") }

    class func hexStr(hexStr: NSString) -> UIColor {
        return UIColor.hexStr(Str: hexStr, alpha: 1)
    }

    class func hexStr(Str: NSString, alpha: CGFloat) -> UIColor {
        let hex = Str.replacingOccurrences(of: "#", with: "")
        let scanner = Scanner(string: hex)
        var color: UInt64 = 0
        if scanner.scanHexInt64(&color) {
            let r = CGFloat((color & 0xFF0000) >> 16) / 255.0
            let g = CGFloat((color & 0x00FF00) >> 8)  / 255.0
            let b = CGFloat(color & 0x0000FF)          / 255.0
            return UIColor(red: r, green: g, blue: b, alpha: alpha)
        }
        print("invalid hex string", terminator: "")
        return UIColor.white
    }

    struct DefaultBar { let start = UIColor.hexStr(hexStr: "FFE512"); let stop = UIColor.hexStr(hexStr: "FFE512") }
    struct OptimumBar  { let start = UIColor.hexStr(hexStr: "2AC706"); let stop = UIColor.hexStr(hexStr: "2AC706") }
    struct WarningBar  { let start = UIColor.hexStr(hexStr: "FD8E02"); let stop = UIColor.hexStr(hexStr: "FD8E02") }
    struct DangerBar   { let start = UIColor.hexStr(hexStr: "D82A2A"); let stop = UIColor.hexStr(hexStr: "D82A2A") }
}

extension Double {
    static func roundedTwoDigit(numberToRound: Double, numberOfDigits: Int) -> Double {
        let divisor = pow(10.0, Double(numberOfDigits))
        return (numberToRound * divisor).rounded() / divisor
    }

    var roundTo1f: Double { return Double.roundedTwoDigit(numberToRound: self, numberOfDigits: 1) }
    var roundTo2f: Double { return Double.roundedTwoDigit(numberToRound: self, numberOfDigits: 2) }
    var roundTo3f: Double { return Double.roundedTwoDigit(numberToRound: self, numberOfDigits: 3) }

    func timeInRedZoneString() -> String {
        let hours   = Int(truncatingRemainder(dividingBy: 86400) / 3600)
        let minutes = Int(truncatingRemainder(dividingBy: 3600)  / 60)
        let seconds = Int(truncatingRemainder(dividingBy: 60))
        return hours > 0
            ? String(format: "%i:%02i:%02i", hours, minutes, seconds)
            : String(format: "%02i:%02i", minutes, seconds)
    }
}
