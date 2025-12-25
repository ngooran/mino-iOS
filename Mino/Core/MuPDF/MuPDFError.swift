//
//  MuPDFError.swift
//  Mino
//
//  Error types for MuPDF operations
//

import Foundation

/// Errors that can occur during MuPDF operations
enum MuPDFError: Error, LocalizedError {
    case contextCreationFailed
    case documentOpenFailed(path: String, reason: String?)
    case invalidPDFDocument
    case compressionFailed(reason: String)
    case saveFailed(reason: String)
    case memoryError
    case invalidParameters
    case fileNotFound(path: String)
    case accessDenied(path: String)
    case unknownError(String)

    var errorDescription: String? {
        switch self {
        case .contextCreationFailed:
            return "Failed to initialize PDF engine"
        case .documentOpenFailed(let path, let reason):
            let file = URL(fileURLWithPath: path).lastPathComponent
            if let reason = reason {
                return "Failed to open '\(file)': \(reason)"
            }
            return "Failed to open '\(file)'"
        case .invalidPDFDocument:
            return "The file is not a valid PDF document"
        case .compressionFailed(let reason):
            return "Compression failed: \(reason)"
        case .saveFailed(let reason):
            return "Failed to save PDF: \(reason)"
        case .memoryError:
            return "Insufficient memory to process the document"
        case .invalidParameters:
            return "Invalid parameters provided"
        case .fileNotFound(let path):
            let file = URL(fileURLWithPath: path).lastPathComponent
            return "File not found: \(file)"
        case .accessDenied(let path):
            let file = URL(fileURLWithPath: path).lastPathComponent
            return "Access denied: \(file)"
        case .unknownError(let message):
            return message
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .contextCreationFailed, .memoryError:
            return "Try closing other apps and try again."
        case .documentOpenFailed, .invalidPDFDocument:
            return "Make sure the file is a valid PDF document."
        case .compressionFailed:
            return "Try using a different compression quality level."
        case .saveFailed, .accessDenied:
            return "Check that you have permission to write to this location."
        case .fileNotFound:
            return "Verify the file exists and try again."
        default:
            return nil
        }
    }
}
