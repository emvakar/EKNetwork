//
//  EKNetworkVersion.swift
//  EKNetwork
//
//  Created by Emil Karimov on 10.06.2025.
//  Copyright © 2025 Emil Karimov. All rights reserved.
//

import Foundation

/// Helper to get EKNetwork version from embedded version file, Bundle, git tag, or fallback
/// When used as SPM dependency, version matches the package version that was connected
enum EKNetworkVersion {
    static let current: String = {
        // Priority 1: Embedded version file (built into the package, most reliable for SPM)
        // This version is set during build from git tag and always matches the connected package version
        // The Version.swift file is updated automatically from git tag before each release
        let embeddedVersion = EKNetworkVersionString
        if !embeddedVersion.isEmpty {
            return embeddedVersion
        }
        
        // Priority 2: Environment variable (set during build, works for SPM)
        if let envVersion = ProcessInfo.processInfo.environment["EKNETWORK_VERSION"], !envVersion.isEmpty {
            return envVersion.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        // Priority 3: Bundle of the framework itself (works for SPM when package has Info.plist)
        let networkBundle = Bundle(for: NetworkManager.self)
        
        // Try CFBundleShortVersionString first
        if let bundleVersion = networkBundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
           !bundleVersion.isEmpty {
            return bundleVersion
        }
        
        // Try CFBundleVersion
        if let bundleVersion = networkBundle.object(forInfoDictionaryKey: kCFBundleVersionKey as String) as? String,
           !bundleVersion.isEmpty {
            return bundleVersion
        }
        
        // Priority 4: Try to get version from git tag in the framework's directory
        // This works when framework is used directly (not as SPM dependency)
        if let frameworkPath = networkBundle.bundlePath as String?,
           let gitVersion = getGitVersion(from: frameworkPath) {
            return gitVersion
        }
        
        // Priority 5: Try to get git version from current working directory
        // (only if framework is in source form, not as SPM dependency)
        if let gitVersion = getGitVersion(from: nil) {
            return gitVersion
        }
        
        // Fallback: use embedded version (should always be set)
        return embeddedVersion
    }()
    
    /// Tries to get git version from the framework's directory or current directory
    /// Note: Only works on macOS and Linux, not available on iOS/watchOS/tvOS
    private static func getGitVersion(from frameworkPath: String?) -> String? {
        #if os(macOS) || os(Linux)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["describe", "--tags", "--abbrev=0"]
        
        // If framework path is provided, try to find git repo relative to it
        if let frameworkPath = frameworkPath {
            // Navigate to framework's directory and try to find git repo
            let url = URL(fileURLWithPath: frameworkPath)
            var currentURL = url
            
            // Walk up the directory tree to find .git folder
            for _ in 0..<10 { // Limit search to 10 levels up
                let gitPath = currentURL.appendingPathComponent(".git")
                if FileManager.default.fileExists(atPath: gitPath.path) {
                    process.currentDirectoryURL = currentURL
                    break
                }
                guard currentURL.pathComponents.count > 1 else { break }
                currentURL = currentURL.deletingLastPathComponent()
            }
        }
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe() // Suppress errors
        
        do {
            try process.run()
            process.waitUntilExit()
            
            if process.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let version = String(data: data, encoding: .utf8) {
                    let trimmed = version.trimmingCharacters(in: .whitespacesAndNewlines)
                    // Remove 'v' prefix if present (e.g., "v1.0.0" -> "1.0.0")
                    return trimmed.hasPrefix("v") ? String(trimmed.dropFirst()) : trimmed
                }
            }
        } catch {
            // Silent fail - will use fallback
        }
        #endif // os(macOS) || os(Linux)
        
        return nil
    }
}

