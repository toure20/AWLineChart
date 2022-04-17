//
//  AWLineChart.swift
//
//  Copyright 2022 TANA (Tudor Octavian Ana)
//
//  Redistribution and use in source and binary forms, with or without modification,
//  are permitted provided that the following conditions are met:
//
//  1. Redistributions of source code must retain the above copyright notice,
//  this list of conditions and the following disclaimer.
//
//  2. Redistributions in binary form must reproduce the above copyright notice,
//  this list of conditions and the following disclaimer in the documentation and/or
//  other materials provided with the distribution.
//
//  THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
//  ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES
//  OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
//  IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT,
//  INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
//  PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
//  HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
//  OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE,
//  EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
//

import UIKit

// MARK: Chart DataSource

public protocol AWLineChartDataSource: AnyObject {
    func numberOfItems(in lineGraph: AWLineChart) -> Int
    func numberOfBottomLabels(in lineGraph: AWLineChart) -> Int
    func numberOfSideLabels(in lineGrapg: AWLineChart) -> Int
    func numberOfVerticalLines(in lineGraph: AWLineChart) -> Int
    func numberOfHorizontalLines(in lineGraph: AWLineChart) -> Int
    func lineGraph(_ lineGraph: AWLineChart, xValueAt index: Int) -> String
    func lineGraph(_ lineGraph: AWLineChart, yValueAt index: Int) -> CGFloat
    func lineGraph(_ lineGraph: AWLineChart, verticalDashPatternAt index: Int) -> [NSNumber]
    func lineGraph(_ lineGraph: AWLineChart, horizontalDashPatternAt index: Int) -> [NSNumber]
}

// MARK: Chart Delegate

public protocol AWLineChartDelegate: AnyObject {
    func lineGraphDidStartRender(_ lineGraph: AWLineChart)
    func lineGraphDidFinishRender(_ lineGraph: AWLineChart)
}

// MARK: Chart data

public protocol AWLineChartData {
    associatedtype FloatingPoint
    var xValue: String { get }
    var yValue: FloatingPoint { get }
}

// MARK: Chart type

public enum AWLineChartType: Int {
    case linear = 0
    case curved = 1
    public init() { self = .linear }
}

// MARK: - UIView

public final class AWLineChart: UIView {

    @IBInspectable public var gridWidth: CGFloat = 0.3
    @IBInspectable public var lineWidth: CGFloat = 3
    @IBInspectable public var sideSpace: CGFloat = 44
    @IBInspectable public var bottomSpace: CGFloat = 44
    @IBInspectable public var showVerticalGrid: Bool = true
    @IBInspectable public var showHorizontalGrid: Bool = true
    @IBInspectable public var showBottomLabels: Bool = true
    @IBInspectable public var showSideLabels: Bool = true
    @IBInspectable public var gridColor: UIColor = .gray
    @IBInspectable public var labelsColor: UIColor = .black
    @IBInspectable public var animationDuration: Float = 0.3
    public var chartType: AWLineChartType = .linear

    fileprivate var minValue: CGFloat = 0.0
    fileprivate var maxValue: CGFloat = 0.0
    fileprivate var graphWidth: CGFloat = 0.0
    fileprivate var graphHeight: CGFloat = 0.0
    fileprivate let padding: CGFloat = 16

    public weak var dataSource: AWLineChartDataSource?
    public weak var delegate: AWLineChartDelegate?

    public override init(frame: CGRect) {
        super.init(frame: frame)
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    public func reloadData(on dispatchQueue: DispatchQueue = .global(qos: .userInitiated)) {
        guard let dataSource = dataSource else { return }
        delegate?.lineGraphDidStartRender(self)
        render(dataSource, dispatchQueue) { [weak self] in
            guard let self = self else { return }
            self.delegate?.lineGraphDidFinishRender(self)
        }
    }
}

// MARK: Helpers

extension AWLineChart {

    fileprivate func render(_ dataSource: AWLineChartDataSource,
                            _ dispatchQueue: DispatchQueue = .global(),
                            _ completion: @escaping () -> Void) {

        // Create a render group
        let renderGroup = DispatchGroup()

        // Remove old layers
        removeLayers()

        // Calculate min and max
        calculateSizes(dataSource)

        // Draw axis
        renderGroup.enter()
        drawAxis(.global()) { layer in
            DispatchQueue.main.async { [weak self] in
                self?.layer.addSublayer(layer)
                renderGroup.leave()
            }
        }

        // Draw vertical grid
        if showVerticalGrid {
            renderGroup.enter()
            drawVerticalGrid(dataSource, .global()) { layer in
                DispatchQueue.main.async { [weak self] in
                    self?.layer.addSublayer(layer)
                    renderGroup.leave()
                }
            }
        }

        // Draw horizontal grid
        if showHorizontalGrid {
            renderGroup.enter()
            drawHorizontalGrid(dataSource, .global()) { layer in
                DispatchQueue.main.async { [weak self] in
                    self?.layer.addSublayer(layer)
                    renderGroup.leave()
                }
            }
        }

        // Draw side labels
        if showSideLabels {
            renderGroup.enter()
            drawSideLabels(dataSource,
                           .main) { [weak self] textLayers in
                               for textLayer in textLayers {
                                   self?.layer.addSublayer(textLayer)
                               }
                               renderGroup.leave()
                           }
        }

        // Draw bottom labels
        if showBottomLabels {
            renderGroup.enter()
            drawBottomLabels(dataSource,
                             .main) { [weak self] textLayers in
                                 for textLayer in textLayers {
                                     self?.layer.addSublayer(textLayer)
                                 }
                                 renderGroup.leave()
                             }
        }

        // Draw chart
        renderGroup.enter()
        drawChart(dataSource,
                  .global()) { layer in
                      DispatchQueue.main.async { [weak self] in
                          self?.layer.addSublayer(layer)
                          renderGroup.leave()
                      }
                  }

        // Wait for everything to draw
        renderGroup.notify(queue: .main) { completion() }
    }

    fileprivate func calculateSizes(_ dataSource: AWLineChartDataSource) {
        graphWidth = frame.size.width - (showSideLabels ? sideSpace : 0)
        graphHeight = frame.size.height - (showBottomLabels ? bottomSpace : 0)
        minValue = CGFloat.greatestFiniteMagnitude
        maxValue = 0.0
        for index in 0..<dataSource.numberOfItems(in: self) {
            let yValue = dataSource.lineGraph(self, yValueAt: index)
            if maxValue < yValue { maxValue = yValue }
            if minValue > yValue { minValue = yValue }
        }
    }

    fileprivate func removeLayers() {
        layer.sublayers?.forEach({ layer in
            layer.removeFromSuperlayer()
        })
    }

    fileprivate func drawVerticalGrid(_ dataSource: AWLineChartDataSource,
                                      _ dispatchQueue: DispatchQueue = .global(),
                                      _ completion: @escaping (CALayer) -> Void) {
        let numOfGrids = min(dataSource.numberOfItems(in: self),
                             dataSource.numberOfVerticalLines(in: self))
        let vSpace = graphWidth / CGFloat(numOfGrids)
        let bounds = bounds

        dispatchQueue.async { [weak self, bounds] in
            guard let self = self else { return }
            let tLayer = CALayer()
            let drawGroup = DispatchGroup()

            for index in 0..<numOfGrids {
                drawGroup.enter()
                self.line(from: CGPoint(x: vSpace * CGFloat(index), y: 0),
                          to: CGPoint(x: vSpace * CGFloat(index), y: self.graphHeight),
                          frame: bounds,
                          color: self.gridColor,
                          width: self.gridWidth,
                          dashPatern: dataSource.lineGraph(self, verticalDashPatternAt: index)) { layer in
                    tLayer.addSublayer(layer)
                    drawGroup.leave()
                }
            }

            drawGroup.notify(queue: .global()) {
                completion(tLayer)
            }
        }
    }

    fileprivate func drawHorizontalGrid(_ dataSource: AWLineChartDataSource,
                                        _ dispatchQueue: DispatchQueue = .global(),
                                        _ completion: @escaping (CALayer) -> Void) {
        let numOfGrids = min(dataSource.numberOfItems(in: self), dataSource.numberOfHorizontalLines(in: self))
        let hSpace = graphHeight / CGFloat(numOfGrids)
        let bounds = bounds

        dispatchQueue.async { [weak self, bounds] in
            guard let self = self else { return }
            let tLayer = CALayer()
            let drawGroup = DispatchGroup()

            for index in 1..<numOfGrids + 1 {
                drawGroup.enter()
                self.line(from: CGPoint(x: 0, y: self.graphHeight - (hSpace * CGFloat(index))),
                          to: CGPoint(x: self.graphWidth, y: self.graphHeight - (hSpace * CGFloat(index))),
                          frame: bounds,
                          color: self.gridColor,
                          width: self.gridWidth,
                          dashPatern: dataSource.lineGraph(self, horizontalDashPatternAt: index)) { layer in
                    tLayer.addSublayer(layer)
                    drawGroup.leave()
                }
            }

            drawGroup.notify(queue: .global()) {
                completion(tLayer)
            }
        }
    }

    fileprivate func drawAxis(_ dispatchQueue: DispatchQueue = .global(),
                              _ completion: @escaping (CALayer) -> Void) {

        let bounds = self.bounds
        dispatchQueue.async { [weak self, bounds] in
            guard let self = self else { return }
            let tLayer = CALayer()
            let drawGroup = DispatchGroup()

            drawGroup.enter()
            self.line(from: CGPoint(x: self.graphWidth, y: 0),
                      to: CGPoint(x: self.graphWidth, y: self.graphHeight),
                      frame: bounds,
                      color: self.gridColor,
                      width: self.gridWidth,
                      dispatchQueue) { layer in
                tLayer.addSublayer(layer)
                drawGroup.leave()
            }

            drawGroup.enter()
            self.line(from: CGPoint(x: 0, y: self.graphHeight),
                      to: CGPoint(x: self.graphWidth, y: self.graphHeight),
                      frame: bounds,
                      color: self.gridColor,
                      width: self.gridWidth,
                      dispatchQueue) { layer in
                tLayer.addSublayer(layer)
                drawGroup.leave()
            }

            drawGroup.notify(queue: .global()) {
                completion(tLayer)
            }
        }
    }

    fileprivate func drawSideLabels(_ dataSource: AWLineChartDataSource,
                                    _ dispatch: DispatchQueue = .main,
                                    _ completion: @escaping ([CATextLayer]) -> Void) {
        dispatch.async { [weak self] in
            guard let self = self else { return }
            var tLayers = [CATextLayer]()
            var values: [CGFloat] = []
            let maxNumberOfLabels = dataSource.numberOfSideLabels(in: self)
            for index in stride(from: self.minValue,
                                to: self.maxValue,
                                by: (self.maxValue - self.minValue) / CGFloat(maxNumberOfLabels)) {
                values.append(index)
            }
            values.append(self.maxValue)
            values = values.sorted()
            let hSpace = self.graphHeight / CGFloat(values.count)
            var drawIndex = 0
            for index in 0..<values.count {
                let label = CATextLayer()
                label.frame = CGRect(x: 0, y: 0, width: self.sideSpace, height: 22)

                var xPos = self.frame.size.width - self.sideSpace / 2
                var yPos = self.graphHeight - (CGFloat(drawIndex) * hSpace)
                if xPos.isNaN { xPos = 0 }
                if yPos.isNaN {
                    if dataSource.lineGraph(self, yValueAt: drawIndex) != 0 {
                        yPos = -10
                    } else {
                        yPos = self.graphHeight - 10
                    }
                }
                label.anchorPoint = CGPoint(x: 0.5, y: 0.8)
                label.position = CGPoint(x: xPos, y: yPos)
                label.alignmentMode = .center
                label.string = "\(values[index].compact())"
                label.font = CGFont(UIFont.systemFont(ofSize: 7.0).fontName as NSString)
                label.fontSize = 10
                label.contentsScale = UIScreen.main.scale
                label.foregroundColor = self.labelsColor.cgColor
                tLayers.append(label)
                drawIndex += 1
            }

            completion(tLayers)
        }
    }

    fileprivate func drawBottomLabels(_ dataSource: AWLineChartDataSource,
                                      _ dispatchQueue: DispatchQueue = .main,
                                      _ completion: @escaping ([CATextLayer]) -> Void) {
        dispatchQueue.async { [weak self] in
            guard let self = self else { return }
            var tLayers = [CATextLayer]()
            var values: [String] = []
            for index in stride(from: 0,
                                to: dataSource.numberOfItems(in: self),
                                by: Int.Stride(ceil(Float(dataSource.numberOfItems(in: self) /
                                                          dataSource.numberOfBottomLabels(in: self))))) {
                values.append(dataSource.lineGraph(self, xValueAt: index))
            }

            let vSpace = self.graphWidth / CGFloat(values.count)
            for index in 0..<values.count {
                let label = CATextLayer()
                var xPos = vSpace * CGFloat(index)
                var yPos = self.graphHeight + self.padding
                if xPos.isNaN { xPos = 0 }
                if yPos.isNaN { yPos = 0 }
                label.alignmentMode = .left
                label.string = values[index]
                label.anchorPoint = CGPoint(x: 1, y: 0)

                let font = UIFont.systemFont(ofSize: 7.0)
                let fontName = font.fontName as NSString
                label.font = CGFont(fontName)
                label.fontSize = 10
                label.contentsScale = UIScreen.main.scale
                label.foregroundColor = self.labelsColor.cgColor
                label.frame = .init(origin: CGPoint(x: xPos, y: yPos),
                                    size: label.preferredFrameSize())

                tLayers.append(label)
            }

            completion(tLayers)
        }
    }

    fileprivate func drawChart(_ dataSource: AWLineChartDataSource,
                               _ dispatchQueue: DispatchQueue = .global(),
                               _ completion: @escaping (CALayer) -> Void) {

        dispatchQueue.async { [weak self] in
            guard let self = self else { return }

            // Create a temporary buffer layer
            let tLayer = CALayer()

            // Draw path
            let vSpace = self.graphWidth / CGFloat(dataSource.numberOfItems(in: self))
            var pointsData: [CGPoint] = []
            for index in 0..<dataSource.numberOfItems(in: self) {

                let xPos = vSpace * CGFloat(index)
                var yPos = self.graphHeight - (CGFloat(dataSource.lineGraph(self, yValueAt: index) -
                                                       self.minValue) * self.graphHeight) /
                CGFloat(self.maxValue - self.minValue)
                if yPos < self.padding { yPos = self.padding }
                if yPos > self.graphHeight - self.padding { yPos = self.graphHeight - self.padding}
                pointsData.append(CGPoint(x: xPos, y: yPos))
            }
            let lineBezierPath = UIBezierPath()
            let gradientBezierPath = UIBezierPath()
            let config = AWBezierConfiguration()
            let controlPoints = config.configureControlPoints(data: pointsData)

            gradientBezierPath.move(to: CGPoint(x: 0, y: self.graphHeight))
            for index in 0 ..< pointsData.count {
                let point = pointsData[index]

                switch index {
                case 0 where self.chartType == .curved:
                    lineBezierPath.move(to: point)
                    gradientBezierPath.addCurve(to: point, controlPoint1: point, controlPoint2: point)
                case 0 where self.chartType == .linear:
                    lineBezierPath.move(to: point)
                    gradientBezierPath.addLine(to: point)
                default:
                    let segment = controlPoints[index - 1]
                    if self.chartType == .curved {
                        var firstControlPoint = segment.firstControlPoint
                        if firstControlPoint.y > self.graphHeight {
                            firstControlPoint.y = self.graphHeight
                        }
                        lineBezierPath.addCurve(to: point,
                                                controlPoint1: segment.firstControlPoint,
                                                controlPoint2: segment.secondControlPoint)
                        gradientBezierPath.addCurve(to: point,
                                                    controlPoint1: segment.firstControlPoint,
                                                    controlPoint2: segment.secondControlPoint)
                    } else {
                        lineBezierPath.addLine(to: point)
                        gradientBezierPath.addLine(to: point)
                    }
                }
            }

            let finalPoint = CGPoint(x: vSpace * (CGFloat(pointsData.count) - 1), y: self.graphHeight)
            gradientBezierPath.addCurve(to: finalPoint, controlPoint1: finalPoint, controlPoint2: finalPoint)
            let shapeLayer = CAShapeLayer()
            shapeLayer.path = lineBezierPath.cgPath
            shapeLayer.lineWidth = self.lineWidth
            shapeLayer.strokeColor = self.tintColor.cgColor
            shapeLayer.fillColor = .none
            shapeLayer.lineCap = .round
            tLayer.addSublayer(shapeLayer)

            // Fill gradient
            let fillGradient = CAGradientLayer()
            fillGradient.frame = self.bounds
            fillGradient.colors = [self.tintColor.withAlphaComponent(0.6).cgColor,
                                   self.tintColor.withAlphaComponent(0.0).cgColor]

            let mask = CAShapeLayer()
            mask.path = gradientBezierPath.cgPath
            mask.lineCap = .round
            mask.fillColor = UIColor.blue.cgColor
            tLayer.insertSublayer(fillGradient, at: 0)
            fillGradient.mask = mask

            // Line gradient
            let lineGradientLayer = CAGradientLayer()
            lineGradientLayer.colors = [self.tintColor.withAlphaComponent(1.0).cgColor,
                                        self.tintColor.withAlphaComponent(0.7).cgColor]
            lineGradientLayer.startPoint = CGPoint(x: 0.5, y: 1.0)
            lineGradientLayer.endPoint = CGPoint(x: 0.5, y: 0.0)
            lineGradientLayer.locations = [0, 1]
            lineGradientLayer.frame = self.bounds
            lineGradientLayer.mask = shapeLayer
            tLayer.insertSublayer(lineGradientLayer, at: 1)

            // Animations
            let lineAnimation = CABasicAnimation(keyPath: "strokeEnd")
            lineAnimation.fromValue = 0.0
            lineAnimation.toValue = 1.0
            lineAnimation.duration = CFTimeInterval(self.animationDuration)
            shapeLayer.add(lineAnimation, forKey: "drawKeyAnimation")

            let gradientAnimation = CABasicAnimation()
            gradientAnimation.fromValue = 0
            gradientAnimation.toValue = 1
            gradientAnimation.duration = 0.7
            gradientAnimation.timingFunction = .init(name: CAMediaTimingFunctionName.easeOut)
            fillGradient.add(gradientAnimation, forKey: "opacity")

            completion(tLayer)
        }
    }
}

extension AWLineChart {

    fileprivate func line(from startPoint: CGPoint,
                          to endPoint: CGPoint,
                          frame: CGRect,
                          value: Double = 0,
                          color: UIColor = .black,
                          width: CGFloat = 1.0,
                          dashPatern: [NSNumber] = [],
                          _ dispatchQueue: DispatchQueue = .global(),
                          _ completion: @escaping (CALayer) -> Void) {

        dispatchQueue.async {
            var xStart = startPoint.x
            var yStart = startPoint.y
            if xStart.isNaN { xStart = 0 }
            if yStart.isNaN {
                if value != 0 {
                    yStart = 0
                } else {
                    yStart = frame.size.height - 22
                }
            }
            var xEnd = endPoint.x
            var yEnd = endPoint.y
            if xEnd.isNaN { xEnd = 0 }
            if yEnd.isNaN {
                if value != 0 {
                    yEnd = 0
                } else {
                    yEnd = frame.size.height - 22
                }
            }

            let line = CAShapeLayer()
            let linePath = UIBezierPath()
            linePath.move(to: CGPoint(x: xStart, y: yStart))
            linePath.addLine(to: CGPoint(x: xEnd, y: yEnd))

            line.path = linePath.cgPath
            line.strokeColor = color.cgColor
            line.lineWidth = width
            line.lineCap = .round
            line.lineDashPattern = dashPatern
            completion(line)
        }
    }
}
