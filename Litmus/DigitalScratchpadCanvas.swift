//
//  DigitalScratchpadCanvas.swift
//  Litmus
//
//  PencilKit wrapper for interactive digital scratchpad drawing.
//

import SwiftUI
import PencilKit

public struct DigitalScratchpadCanvas: UIViewRepresentable {
    @Binding var canvasView: PKCanvasView
    var onDrawingChanged: (() -> Void)? = nil
    
    public init(canvasView: Binding<PKCanvasView>, onDrawingChanged: (() -> Void)? = nil) {
        self._canvasView = canvasView
        self.onDrawingChanged = onDrawingChanged
    }
    
    public func makeUIView(context: Context) -> PKCanvasView {
        canvasView.tool = PKInkingTool(.pen, color: .white, width: 3)
        canvasView.backgroundColor = .clear
        canvasView.isOpaque = false
        if #available(iOS 14.0, *) {
            canvasView.drawingPolicy = .anyInput
        }
        canvasView.delegate = context.coordinator
        return canvasView
    }
    
    public func updateUIView(_ uiView: PKCanvasView, context: Context) {
        // State updates if necessary
    }
    
    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    public class Coordinator: NSObject, PKCanvasViewDelegate {
        var parent: DigitalScratchpadCanvas
        
        init(_ parent: DigitalScratchpadCanvas) {
            self.parent = parent
        }
        
        public func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            parent.onDrawingChanged?()
        }
    }
}
