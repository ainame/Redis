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

/// A Config bundels together the information needed to
/// create a socket
public struct Config {
    public var addressFamily: AddressFamily
    public let socketType: SocketType
    public let protocolType: Protocol
    public var reuseAddress: Bool = true

    public init(
        addressFamily: AddressFamily,
        socketType: SocketType,
        protocolType: Protocol
    ) {
        self.addressFamily = addressFamily
        self.socketType = socketType
        self.protocolType = protocolType
    }

    public static func TCP(
        addressFamily: AddressFamily = .unspecified
    ) -> Config {
        return self.init(
            addressFamily: addressFamily,
            socketType: .stream,
            protocolType: .TCP
        )
    }

    public static func UDP(
        addressFamily: AddressFamily = .unspecified
    ) -> Config {
        return self.init(
            addressFamily: addressFamily,
            socketType: .datagram,
            protocolType: .UDP
        )
    }
}
