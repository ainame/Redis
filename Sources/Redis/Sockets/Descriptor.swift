// This file is cited from https://github.com/vapor/sockets
//
// The MIT License (MIT)
// 
// Copyright (c) 2016 Qutheory, LLC
// 
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
// 
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
// 
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

import Libc

public struct Descriptor {
    public let raw: Int32
    public init(_ raw: Int32) {
        self.raw = raw
    }

    public init(_ config: Config) throws {
        let cProtocolFam = config.addressFamily.toCType()
        let cType = config.socketType.toCType()
        let cProtocol = config.protocolType.toCType()

        let descriptor = socket(cProtocolFam, cType, cProtocol)
        guard descriptor >= 0 else { throw SocketsError(.createSocketFailed) }
        self.raw = descriptor

        if config.reuseAddress {
            try setOption(level: SOL_SOCKET, name: SO_REUSEADDR, value: 1)
        }

        try disableSIGPIPE()
    }
}

public protocol DescriptorRepresentable {
    func makeDescriptor() -> Descriptor
}

extension Descriptor: ExpressibleByIntegerLiteral {
    public init(integerLiteral value: Int32) {
        self.init(value)
    }
}


#if os(Linux)
private let SOCKET_NOSIGNAL = Int32(MSG_NOSIGNAL)
#else
private let SOCKET_NOSIGNAL = SO_NOSIGPIPE
#endif


extension Descriptor {
    /// prevents SIGPIPE from killing process
    func disableSIGPIPE() throws {
        signal(SIGPIPE, SIG_IGN)
        #if !os(Linux)
        try setOption(
            level: SOL_SOCKET,
            name: SOCKET_NOSIGNAL,
            value: 1
        )
        #endif
    }

    func setBoolOption(
        level: Int32,
        name: Int32,
        value: Bool
    ) throws {
        let val = value ? 1 : 0
        try setOption(
            level: level,
            name: name,
            value: val
        )
    }

    func getBoolOption(level: Int32, name: Int32) throws -> Bool {
        return try getOption(level: level, name: name) > 0
    }

    func setOption<T>(level: Int32, name: Int32, value: T) throws {
        var val = value
        guard setsockopt(
            raw,
            level,
            name,
            &val,
            socklen_t(MemoryLayout<T>.stride)
        ) != -1 else {
            throw SocketsError(
                .optionSetFailed(
                    level: level,
                    name: name,
                    value: String(describing: value)
                )
            )
        }
    }

    func getOption<T>(level: Int32, name: Int32) throws -> T {
        var length = socklen_t(MemoryLayout<T>.stride)
        var val = UnsafeMutablePointer<T>.allocate(capacity: 1)
        defer {
            val.deinitialize()
            val.deallocate(capacity: 1)
        }
        guard getsockopt(raw, level, name, val, &length) != -1 else {
            throw SocketsError(
                .optionGetFailed(
                    level: level,
                    name: name,
                    type: String(describing: T.self)
                )
            )
        }
        return val.pointee
    }
}
