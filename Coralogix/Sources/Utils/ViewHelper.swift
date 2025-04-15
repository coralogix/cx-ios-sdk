//
//  CXHelper.swift
//
//
//  Created by Coralogix DEV TEAM on 23/07/2024.
//

import Foundation
#if canImport(UIKit)
import UIKit
#endif
import CoralogixInternal

class ViewHelper {
    static func cxElementForView(view: UIView?) -> [String: Any]? {
        guard let view = view else {
            return nil
        }
        let isClickable = self.isClickableControlOrView(view: view) || self.isClickableCellOrRow(view: view)
        if let text = ViewHelper.extractTextsFrom(view: view) {
            Log.d("isClickable: \(isClickable), text: \(text)")
        }
        return [String: Any]()
    }
    
    static private func isClickableControlOrView(view: UIView) -> Bool {
        if view is UIControl {
            return true
        }
        
        var isClickableView = self.isClickableView(view: view)
        if !isClickableView {
            isClickableView = ViewHelper.isSwiftUIView(view: view)
        }
        return isClickableView
    }
    
    static private func isClickableView(view: UIView) -> Bool {
        let className = NSStringFromClass(type(of: view))
        return self.hasGesture(view: view, className: className) || self.isAlertActionView(className: className)
    }
    
    static private func hasGesture(view: UIView, className: String) -> Bool {
        guard let gestureRecognizers = view.gestureRecognizers, gestureRecognizers.count == 0 else {
            return false
        }
        
        let isGestureIgnoredClass = self == UIWindow.self ||
        self == UIControl.self ||
        self == UIScrollView.self ||
        self == UISearchBar.self ||
        self == UITabBar.self ||
        self == UINavigationBar.self
        
        return !isGestureIgnoredClass
    }
    
    static private func isAlertActionView(className: String) -> Bool {
        return className == "_UIAlertControllerActionView"
    }
    
    static private func isClickableCellOrRow(view: UIView) -> Bool {
        return false
    }
    
    static func extractTextsFrom(view: UIView) -> String? {
        if let label = view as? UILabel {
            return label.text
        } else if let button = view as? UIButton {
            return button.title(for: .normal)
        } else if let textView = view as? UITextView {
            return textView.text
        } else if let segment = view as? UISegmentedControl {
            let selected = segment.selectedSegmentIndex
            if selected < segment.numberOfSegments {
                return segment.titleForSegment(at: selected)
            }
        } else if let tableViewCell = view as? UITableViewCell {
            return tableViewCell.textLabel?.text
        } else if ViewHelper.isSwiftUIView(view: view) {
            return view.layer.debugDescription
        }
        return nil
    }
    
    static func isSwiftUIView(view: UIView) -> Bool {
        let className = NSStringFromClass(type(of: view))
        return className.contains("DrawingView") ||
            className.contains("UIGraphicsView") ||
            className.contains("SwiftUI")
    }
    
    static func printClassDetails(view: UIView) {
        let className = NSStringFromClass(type(of: view))
        print("Class: \(className)")
        if let cls = NSClassFromString(className) {
            // Print methods
            var methodCount: UInt32 = 0
            if let methods = class_copyMethodList(cls, &methodCount) {
                print("Methods:")
                for index in 0..<Int(methodCount) {
                    let method = methods[index]
                    let selector = method_getName(method)
                    let name = NSStringFromSelector(selector)
                    print("  \(name)")
                }
                free(methods)
            }
            
            // Print properties
            var propertyCount: UInt32 = 0
            if let properties = class_copyPropertyList(cls, &propertyCount) {
                print("Properties:")
                for index in 0..<Int(propertyCount) {
                    let property = properties[index]
                    let name = String(cString: property_getName(property))
                    print("  \(name)")
                }
                free(properties)
            }
            
            // Print ivars
            var ivarCount: UInt32 = 0
            if let ivars = class_copyIvarList(cls, &ivarCount) {
                print("Ivars:")
                for index in 0..<Int(ivarCount) {
                    let ivar = ivars[index]
                    let name = String(cString: ivar_getName(ivar)!)
                    print("  \(name)")
                }
                free(ivars)
            }
            
            // Print protocols
            var protocolCount: UInt32 = 0
            if let protocols = class_copyProtocolList(cls, &protocolCount) {
                print("Protocols:")
                for index in 0..<Int(protocolCount) {
                    let proto = protocols[index]
                    let name = String(cString: protocol_getName(proto))
                    print("  \(name)")
                }
            }
        }
    }
    
    static func extractTitleUITabBarItem(from description: String) -> String? {
        let pattern = "title='([^']+)'"
        if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
            let nsRange = NSRange(description.startIndex..<description.endIndex, in: description)
            if let match = regex.firstMatch(in: description, options: [], range: nsRange) {
                if let titleRange = Range(match.range(at: 1), in: description) {
                    return String(description[titleRange])
                }
            }
        }
        return nil
    }
}
