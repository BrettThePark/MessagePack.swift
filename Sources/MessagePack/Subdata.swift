//
//  Subdata.swift
//  MessagePack
//
//  Created by Brett Park on 2021-01-08.
//

import Foundation

/// Handle the remaining data without duplicating
public final class Subdata {
  let base: Data
  /// Current location of where we are processing
  private var offset: Int = 0 {
    didSet {
      isEmpty = offset >= base.endIndex
    }
  }
  
  /// Initialize with the original data source
  ///
  /// - Parameter data: The data to be unpacked
  init(_ data: Data) {
    self.base = data
    isEmpty = data.isEmpty
  }
  
  
  /// Determine if we are out of data
  public private (set) var isEmpty: Bool
  
  
  /// The first byte at the offset
  var first: UInt8? {
    guard !isEmpty else {
      return nil
    }
    
    return base[offset]
  }
  
  
  /// Total number of bytes left
  var count: Int {
    return base.endIndex - offset
  }
  
  
  /// Advance the location of our remaining data
  ///
  /// - Parameter size: Number of bytes to advance
  func inc(_ size:Int) {
    offset += size
  }
  
  
  /// Return the first byte and advance subdata
  ///
  /// - Returns: The first byte at offset
  func popOne() -> UInt8 {
    let v = base[offset]
    offset += 1
    return v
  }
  
  
  /// Pop a types object off the data
  ///
  /// - Parameters:
  ///   - type: Type of data to return
  ///   - inc: Number of bytes to advance our subdata data
  /// - Returns: The object that was popped
  func pop<T>(_ type: T.Type, inc:Int) -> T {
    let v:T = base.withUnsafeBytes { (rawDataBytes:UnsafePointer<UInt8>) -> T in
        let unsafePointer = UnsafeRawPointer(rawDataBytes)
        return unsafePointer.load(fromByteOffset: offset, as: T.self) as T
    }
    
    offset += inc
    return v
  }
  
  
  /// Pop back a data object with copied Memory
  ///
  /// - Parameter size: Size of the data object to return
  /// - Returns: A data object with the same backing as the original
  func popData(first size: Int) -> Data {
    let subdata = base.subdata(in: offset..<(offset+size))
    offset += size
    return subdata
  }
}
