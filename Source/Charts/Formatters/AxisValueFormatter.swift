//
//  AxisValueFormatter.swift
//  Charts
//
//  Copyright 2015 Daniel Cohen Gindi & Philipp Jahoda
//  A port of MPAndroidChart for iOS
//  Licensed under Apache License 2.0
//
//  https://github.com/ChartsOrg/Charts
//

import Foundation

#if canImport(UIKit)
import UIKit
#endif

/// An interface for providing custom axis Strings.
@objc(ChartAxisValueFormatter)
public protocol AxisValueFormatter: AnyObject
{

    /// Called when a value from an axis is formatted before being drawn.
    ///
    /// For performance reasons, avoid excessive calculations and memory allocations inside this method.
    ///
    /// - Parameters:
    ///   - value:           the value that is currently being drawn
    ///   - axis:            the axis that the value belongs to
    /// - Returns: The customized label that is drawn on the x-axis.
    func stringForValue(_ value: Double,
                        axis: AxisBase?) -> String

    /// Optional: return player image data for x-axis icon rendering.
    /// Conformers that don't implement this get plain text labels.
    @objc optional func imageForValue(_ value: Double, axis: AxisBase?) -> xAxisParts?

}

/// Container for x-axis player icon data. Return from imageForValue(_:axis:) in your AxisValueFormatter.
open class xAxisParts: NSObject {
    open var playerImage: UIImage
    open var isBenched: Bool

    public override init() {
        playerImage = UIImage()
        isBenched = false
        super.init()
    }
}
