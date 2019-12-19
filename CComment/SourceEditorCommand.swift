//
//  SourceEditorCommand.swift
//  CComment
//
//  Created by flexih on 7/24/16.
//  Copyright © 2016 flexih. All rights reserved.
//

import Foundation
import XcodeKit

enum CommentStatus {
    case Plain
    case Unpair
    case Pair(range: NSRange)
}

fileprivate struct Constants {
    static let startSymbol = "/*"
    static let endSymbol = "*/"
}

class SourceEditorCommand: NSObject, XCSourceEditorCommand {
    
    func perform(with invocation: XCSourceEditorCommandInvocation, completionHandler: @escaping (Error?) -> Swift.Void ) {
        
        let buffer = invocation.buffer
        let selections = buffer.selections
        
        selections.forEach {
            let range = $0 as! XCSourceTextRange
            if range.start.line == range.end.line && range.start.column == range.end.column {
                let fake: XCSourceTextRange = range
                let lineText = buffer.lines[fake.start.line] as! String
                
                fake.start.column = 0
                fake.end.column = lineText.distance(from: lineText.startIndex, to: lineText.endIndex) - 1
                
                if fake.end.column > fake.start.column {
                    handle(range: fake, inBuffer: buffer)
                }
                
            } else {
                
                handle(range: range, inBuffer: buffer)
            }
        }
        
        completionHandler(nil)
    }
    
    func handle(range: XCSourceTextRange, inBuffer buffer: XCSourceTextBuffer) -> () {
        let selectedText = text(inRange: range, inBuffer: buffer)
        let status = selectedText.commentStatus
        let startSymbolLength = Constants.startSymbol.count
        let endSymbolLength = Constants.endSymbol.count
        
        switch status {
        case .Unpair:
            break
        case .Plain:
            insert(position: range.end, with: Constants.endSymbol, inBuffer: buffer)
            insert(position: range.start, with: Constants.startSymbol, inBuffer: buffer)
            
            // Fix selection
            let sameLine = range.start.line == range.end.line
            let offset = sameLine ? startSymbolLength + endSymbolLength : endSymbolLength
            offsetSelection(range, by: offset)
        case .Pair(let commentedRange):
            let startPair = position(range.start, offsetBy: commentedRange.location, inBuffer: buffer)
            let endPair = position(range.start, offsetBy: commentedRange.location + commentedRange.length, inBuffer: buffer)
            
            replace(position: endPair, length: -endSymbolLength, with: "", inBuffer: buffer)
            replace(position: startPair, length: startSymbolLength, with: "", inBuffer: buffer)
            
            // Fix selection
            range.start = startPair
            range.end = endPair
            let sameLine = range.start.line == range.end.line
            let offset = sameLine ? startSymbolLength + endSymbolLength : endSymbolLength
            offsetSelection(range, by: -offset)
        }
    }
    
    func text(inRange textRange: XCSourceTextRange, inBuffer buffer: XCSourceTextBuffer) -> String {
        if textRange.start.line == textRange.end.line {
            let lineText = buffer.lines[textRange.start.line] as! String
            let from = lineText.index(lineText.startIndex, offsetBy: textRange.start.column)
            let to = lineText.index(lineText.startIndex, offsetBy: textRange.end.column)
            return String(lineText[from..<to])
        }
        
        var text = ""
        
        for aLine in textRange.start.line...textRange.end.line {
            let lineText = buffer.lines[aLine] as! String
            
            switch aLine {
            case textRange.start.line:
                text += lineText[lineText.index(lineText.startIndex, offsetBy: textRange.start.column)...]
            case textRange.end.line:
                text += lineText[..<lineText.index(lineText.startIndex, offsetBy: textRange.end.column)]
            default:
                text += lineText
            }
        }
        
        return text
    }
    
    func position(_ i: XCSourceTextPosition, offsetBy: Int, inBuffer buffer: XCSourceTextBuffer) -> XCSourceTextPosition {
        var aLine = i.line
        var aLineColumn = i.column
        var n = offsetBy
        
        repeat {
            let aLineCount = (buffer.lines[aLine] as! String).count
            let leftInLine = aLineCount - aLineColumn
            
            if leftInLine <= n {
                n -= leftInLine
            } else {
                return XCSourceTextPosition(line: aLine, column: aLineColumn + n)
            }
            
            aLine += 1
            aLineColumn = 0
            
        } while aLine < buffer.lines.count
        
        return i
    }
    
    func replace(position: XCSourceTextPosition, length: Int, with newElements: String, inBuffer buffer: XCSourceTextBuffer) {
        var lineText = buffer.lines[position.line] as! String
        
        var start = lineText.index(lineText.startIndex, offsetBy: position.column)
        var end = lineText.index(start, offsetBy: length)
        
        if length < 0 {
            swap(&start, &end)
        }

        lineText.replaceSubrange(start..<end, with: newElements)
        lineText.remove(at: lineText.index(before: lineText.endIndex)) //remove end "\n"
        
        buffer.lines[position.line] = lineText
    }
    
    func insert(position: XCSourceTextPosition, with newElements: String, inBuffer buffer: XCSourceTextBuffer) {
        var lineText = buffer.lines[position.line] as! String
        
        var start = lineText.index(lineText.startIndex, offsetBy: position.column)
        
        if start >= lineText.endIndex {
            start = lineText.index(before: lineText.endIndex)
        }
        
        lineText.insert(contentsOf: newElements, at: start)
        lineText.remove(at: lineText.index(before: lineText.endIndex)) //remove end "\n"
        
        buffer.lines[position.line] = lineText
    }
    
    func offsetSelection(_ selection: XCSourceTextRange, by offset: Int) {
        selection.end.column += offset
    }
    
}

extension String {
    
    var commentedRange: NSRange? {
        do {
            let expression = try NSRegularExpression(pattern: "/\\*[\\s\\S]*\\*/", options: [])
            let matches = expression.matches(in: self, options: [], range: NSRange(location: 0, length: self.distance(from: self.startIndex, to: self.endIndex)))
            return matches.first?.range
            
        } catch {
            
        }
        
        return nil
    }
    
    var isUnpairCommented: Bool {
        if let i = firstIndex(of: "*") {
            if i > startIndex && i < endIndex {
                if self[index(before: i)] == "/" ||
                    self[index(after: i)] == "/" {
                    return true
                }
            }
        }
        
        return false
    }
    
    var commentStatus: CommentStatus {
        if let range = commentedRange {
            return .Pair(range: range)
        }
        
        if isUnpairCommented {
            return .Unpair
        }
        
        return .Plain
    }
    
}
