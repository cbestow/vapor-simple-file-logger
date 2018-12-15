//
//  SimpleFileLogger.swift
//  SimpleFileLogger
//
//  Created by Hal Lee on 9/8/18.
//

import Vapor

public final class SimpleFileLogger: Logger {
    
    public enum Component {
        case fileInfo
        case level
        case message
        case timestamp
    }
    
    let executableName: String
    let components: [Component]
    let separator: String
    let fileManager = FileManager.default
    let fileQueue = DispatchQueue.init(label: "vaporSimpleFileLogger", qos: .utility)
    var fileHandles = [URL: Foundation.FileHandle]()
    lazy var logDirectoryURL: URL? = {
        var baseURL: URL?
        #if os(macOS)
        /// ~/Library/Caches/
        if let url = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first {
            baseURL = url
        } else { print("Unable to find caches directory.") }
        #endif
        #if os(Linux)
        baseURL = URL(fileURLWithPath: "/var/log/")
        #endif
        
        /// Append executable name; ~/Library/Caches/executableName/ (macOS),
        /// or /var/log/executableName/ (Linux)
        do {
            if let executableURL = baseURL?.appendingPathComponent(executableName, isDirectory: true) {
                try fileManager.createDirectory(at: executableURL, withIntermediateDirectories: true, attributes: nil)
                baseURL = executableURL
            }
        } catch { print("Unable to create \(executableName) log directory.") }
        
        return baseURL
    }()
    
    public init(executableName: String = "Vapor",
                includeTimestamps: Bool = false,
                components: [Component] = [],
                separator: String = "\u{20}") {
        var components = components
        
        if components.isEmpty {
            if includeTimestamps {
                components = [.timestamp]
            }
            components += [.level, .message, .fileInfo]
        }
        
        self.components = components
        self.separator = separator
        self.executableName = executableName
        // TODO: sanitize executableName for path use
    }
    
    deinit {
        for (_, handle) in fileHandles {
            handle.closeFile()
        }
    }
    
    public func log(_ string: String, at level: LogLevel, file: String, function: String, line: UInt, column: UInt) {
        let fileName = level.description.lowercased() + ".log"
        var output: [String] = []
        
        for component in components {
            switch component {
            case .fileInfo:
                output.append("(\(file):\(line))")
            case .level:
                output.append("[ \(level.description) ]")
            case .message:
                output.append(string)
            case .timestamp:
                output.append(Date().description)
            }
        }
        
        saveToFile(output.joined(separator: self.separator), fileName: fileName)
    }
    
    func saveToFile(_ string: String, fileName: String) {
        guard let baseURL = logDirectoryURL else { return }
        
        fileQueue.async {
            let url = baseURL.appendingPathComponent(fileName, isDirectory: false)
            let output = string + "\n"
            
            do {
                if !self.fileManager.fileExists(atPath: url.path) {
                    try output.write(to: url, atomically: true, encoding: .utf8)
                } else {
                    let fileHandle = try self.fileHandle(for: url)
                    fileHandle.seekToEndOfFile()
                    if let data = output.data(using: .utf8) {
                        fileHandle.write(data)
                    }
                }
            } catch {
                print("SimpleFileLogger could not write to file \(url).")
            }
        }
    }
    
    /// Retrieves an opened FileHandle for the given file URL,
    /// or creates a new one.
    func fileHandle(for url: URL) throws -> Foundation.FileHandle {
        if let opened = fileHandles[url] {
            return opened
        } else {
            let handle = try FileHandle(forWritingTo: url)
            fileHandles[url] = handle
            return handle
        }
    }
    
}

extension SimpleFileLogger: ServiceType {
    
    public static var serviceSupports: [Any.Type] {
        return [Logger.self]
    }
    
    public static func makeService(for worker: Container) throws -> SimpleFileLogger {
        return SimpleFileLogger()
    }
    
}