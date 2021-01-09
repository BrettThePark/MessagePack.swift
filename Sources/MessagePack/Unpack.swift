
import Foundation


/// Joins bytes to form an integer.
///
/// - parameter data: The input data to unpack.
/// - parameter size: The size of the integer.
///
/// - returns: An integer representation of `size` bytes of data.
func unpackInteger(_ data: Subdata, count: Int) throws -> (value: UInt64, subdata: Subdata) {
    guard count > 0 else {
        throw MessagePackError.invalidArgument
    }

    guard data.count >= count else {
        throw MessagePackError.insufficientData
    }

    var value: UInt64 = 0
    for _ in 0 ..< count {
    let byte = data.popOne()
        value = value << 8 | UInt64(byte)
    }

  return (value, data)
}

/// Joins bytes to form a string.
///
/// - parameter data: The input data to unpack.
/// - parameter length: The length of the string.
///
/// - returns: A string representation of `size` bytes of data.
func unpackString(_ data: Subdata, count: Int) throws -> (value: String, subdata: Subdata) {
    guard count > 0 else {
        return ("", data)
    }

    guard data.count >= count else {
        throw MessagePackError.insufficientData
    }


    let subdata = data.popData(first: count)
    guard let result = String(data: subdata, encoding: .utf8) else {
        throw MessagePackError.invalidData
    }

  return (result, data)
}

/// Joins bytes to form a data object.
///
/// - parameter data: The input data to unpack.
/// - parameter length: The length of the data.
///
/// - returns: A subsection of data representing `size` bytes.
func unpackData(_ data: Subdata, count: Int) throws -> (value: Data, subdata: Subdata) {
    guard count > 0 else {
        throw MessagePackError.invalidArgument
    }

    guard data.count >= count else {
        throw MessagePackError.insufficientData
    }
  let subData = data.popData(first: count)
  return (subData, data)
}

/// Joins bytes to form an array of `MessagePackValue` values.
///
/// - parameter data: The input data to unpack.
/// - parameter count: The number of elements to unpack.
///
/// - returns: An array of `count` elements.
func unpackArray(_ data: Subdata, count: Int, compatibility: Bool) throws -> (value: [MessagePackValue], subdata: Subdata) {
  var values = [MessagePackValue]()
    var newValue: MessagePackValue
  var subdata:Subdata = data
    for _ in 0 ..< count {
        (newValue, subdata) = try unpack(subdata, compatibility: compatibility)
        values.append(newValue)
    }

    return (values, subdata)
}

/// Joins bytes to form a dictionary with `MessagePackValue` key/value entries.
///
/// - parameter data: The input data to unpack.
/// - parameter count: The number of elements to unpack.
///
/// - returns: An dictionary of `count` entries.
func unpackMap(_ data: Subdata, count: Int, compatibility: Bool) throws -> (value: [MessagePackValue: MessagePackValue], subdata: Subdata) {
    var dict = [MessagePackValue: MessagePackValue](minimumCapacity: count)
    var lastKey: MessagePackValue? = nil

    let (array, subdata) = try unpackArray(data, count: 2 * count, compatibility: compatibility)
    for item in array {
        if let key = lastKey {
            dict[key] = item
            lastKey = nil
        } else {
            lastKey = item
        }
    }

    return (dict, subdata)
}

/// Unpacks data into a MessagePackValue and returns the remaining data.
///
/// - parameter data: The input data to unpack.
///
/// - returns: A `MessagePackValue`.
public func unpack(_ data: Data, compatibility: Bool = false) throws -> (value: MessagePackValue, subdata: Subdata) {
  let (value, subdata) = try unpack(Subdata(data), compatibility: compatibility)
  return (value, subdata)
}



public func unpack(_ data: Subdata, compatibility: Bool = false) throws -> (value: MessagePackValue, subdata: Subdata) {
    guard !data.isEmpty else {
        throw MessagePackError.insufficientData
    }

  let value = data.popOne()

    switch value {

    // positive fixint
    case 0x00 ... 0x7f:
        return (.uint(UInt64(value)), data)

    // fixmap
    case 0x80 ... 0x8f:
        let count = Int(value - 0x80)
        let (dict, subdata) = try unpackMap(data, count: count, compatibility: compatibility)
        return (.map(dict), subdata)

    // fixarray
    case 0x90 ... 0x9f:
        let count = Int(value - 0x90)
        let (array, subdata) = try unpackArray(data, count: count, compatibility: compatibility)
        return (.array(array), subdata)

    // fixstr
    case 0xa0 ... 0xbf:
        let count = Int(value - 0xa0)
        if compatibility {
            let (data, subdata) = try unpackData(data, count: count)
            return (.binary(data), subdata)
        } else {
            let (string, subdata) = try unpackString(data, count: count)
            return (.string(string), subdata)
        }

    // nil
    case 0xc0:
        return (.nil, data)

    // false
    case 0xc2:
        return (.bool(false), data)

    // true
    case 0xc3:
        return (.bool(true), data)

    // bin 8, 16, 32
    case 0xc4 ... 0xc6:
        let intCount = 1 << Int(value - 0xc4)
        let (dataCount, subdata1) = try unpackInteger(data, count: intCount)
        let (subdata, subdata2) = try unpackData(subdata1, count: Int(dataCount))
        return (.binary(subdata), subdata2)

    // ext 8, 16, 32
    case 0xc7 ... 0xc9:
        let intCount = 1 << Int(value - 0xc7)

        let (dataCount, subdata1) = try unpackInteger(data, count: intCount)
        guard !subdata1.isEmpty else {
            throw MessagePackError.insufficientData
        }

    let type = Int8(bitPattern: subdata1.popOne())
    let (data, subdata2) = try unpackData(subdata1, count: Int(dataCount))
        return (.extended(type, data), subdata2)

    // float 32
    case 0xca:
        let (intValue, subdata) = try unpackInteger(data, count: 4)
        let float = Float(bitPattern: UInt32(truncatingBitPattern: intValue))
        return (.float(float), subdata)

    // float 64
    case 0xcb:
        let (intValue, subdata) = try unpackInteger(data, count: 8)
        let double = Double(bitPattern: intValue)
        return (.double(double), subdata)

    // uint 8, 16, 32, 64
    case 0xcc ... 0xcf:
        let count = 1 << (Int(value) - 0xcc)
        let (integer, subdata) = try unpackInteger(data, count: count)
        return (.uint(integer), subdata)

    // int 8
    case 0xd0:
        guard !data.isEmpty else {
            throw MessagePackError.insufficientData
        }

    let byte = Int8(bitPattern: data.popOne())
    return (.int(Int64(byte)), data)

    // int 16
    case 0xd1:
        let (bytes, subdata) = try unpackInteger(data, count: 2)
        let integer = Int16(bitPattern: UInt16(truncatingBitPattern: bytes))
        return (.int(Int64(integer)), subdata)

    // int 32
    case 0xd2:
        let (bytes, subdata) = try unpackInteger(data, count: 4)
        let integer = Int32(bitPattern: UInt32(truncatingBitPattern: bytes))
        return (.int(Int64(integer)), subdata)

    // int 64
    case 0xd3:
        let (bytes, subdata) = try unpackInteger(data, count: 8)
        let integer = Int64(bitPattern: bytes)
        return (.int(integer), subdata)

    // fixent 1, 2, 4, 8, 16
    case 0xd4 ... 0xd8:
        let count = 1 << Int(value - 0xd4)

        guard !data.isEmpty else {
            throw MessagePackError.insufficientData
        }

    let type = Int8(bitPattern: data.popOne())
    let (bytes, subdata) = try unpackData(data, count: count)
        return (.extended(type, bytes), subdata)

    // str 8, 16, 32
    case 0xd9 ... 0xdb:
        let countSize = 1 << Int(value - 0xd9)
        let (count, subdata1) = try unpackInteger(data, count: countSize)
        if compatibility {
            let (data, subdata2) = try unpackData(subdata1, count: Int(count))
            return (.binary(data), subdata2)
        } else {
            let (string, subdata2) = try unpackString(subdata1, count: Int(count))
            return (.string(string), subdata2)
        }

    // array 16, 32
    case 0xdc ... 0xdd:
        let countSize = 1 << Int(value - 0xdb)
        let (count, subdata1) = try unpackInteger(data, count: countSize)
        let (array, subdata2) = try unpackArray(subdata1, count: Int(count), compatibility: compatibility)
        return (.array(array), subdata2)

    // map 16, 32
    case 0xde ... 0xdf:
        let countSize = 1 << Int(value - 0xdd)
        let (count, subdata1) = try unpackInteger(data, count: countSize)
        let (dict, subdata2) = try unpackMap(subdata1, count: Int(count), compatibility: compatibility)
        return (.map(dict), subdata2)

    // negative fixint
    case 0xe0 ..< 0xff:
        return (.int(Int64(value) - 0x100), data)

    // negative fixint (workaround for rdar://19779978)
    case 0xff:
        return (.int(Int64(value) - 0x100), data)

    default:
        throw MessagePackError.invalidData
    }
}

/// Unpacks a data object into a `MessagePackValue`, ignoring excess data.
///
/// - parameter data: The data to unpack.
///
/// - returns: The contained `MessagePackValue`.
public func unpackFirst(_ data: Data, compatibility: Bool = false) throws -> MessagePackValue {
    return try unpack(Subdata(data), compatibility: compatibility).value
}

/// Unpacks a data object into an array of `MessagePackValue` values.
///
/// - parameter data: The data to unpack.
///
/// - returns: The contained `MessagePackValue` values.
public func unpackAll(_ originalData: Data, compatibility: Bool = false) throws -> [MessagePackValue] {
    var values = [MessagePackValue]()

    var data = Subdata(originalData)
    while !data.isEmpty {
        let value: MessagePackValue
        (value, data) = try unpack(data, compatibility: compatibility)
        values.append(value)
    }

    return values
}
