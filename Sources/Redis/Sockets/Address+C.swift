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

#if os(Linux)
    import Glibc
    typealias socket_addrinfo = Glibc.addrinfo
#else
    import Darwin
    typealias socket_addrinfo = Darwin.addrinfo
#endif

//Pretty types -> C types

protocol InternetAddressResolver {
    func resolve(_ internetAddress: InternetAddress, with config: inout Config) throws -> ResolvedInternetAddress
}

// Brief:   Given a hostname and a service this struct returns a list of
//          IP and Port adresses that where obtained during the name resolution
//          e.g. "localhost" and "echo" as arguments will result in a list of
//          IP addresses of the machine that runs the program and port set to 7
//
struct Resolver: InternetAddressResolver{

    // config       -   the provided Config object guides the name resolution
    //                  the socketType and protocolType fields control which kind
    //                  kind of socket you want to create.
    //                  E.g. set them to .STREAM .TCP to obtain address for a TCP Stream socket
    //              -   Set the addressFamily field to .UNSPECIFIED if you don't care if the
    //                  name resolution leads to IPv4 or IPv6 addresses.
    func resolve(_ internetAddress: InternetAddress, with config: inout Config) throws -> ResolvedInternetAddress {

                //
        // Narrowing down the results we will get from the getaddrinfo call
        //
        var addressCriteria = socket_addrinfo.init()
        // IPv4 or IPv6
        addressCriteria.ai_family = config.addressFamily.toCType()
        addressCriteria.ai_flags = AI_PASSIVE
        addressCriteria.ai_socktype = config.socketType.toCType()
        addressCriteria.ai_protocol = config.protocolType.toCType()
        
        // The list of addresses that correspond to the hostname/service pair.
        // servinfo is the first node in a linked list of addresses that is empty
        // at this line
        var servinfo: UnsafeMutablePointer<socket_addrinfo>? = nil
        // perform resolution
        let ret = getaddrinfo(internetAddress.hostname, internetAddress.port.toString(), &addressCriteria, &servinfo)
        guard ret == 0 else {
            let reason = String(validatingUTF8: gai_strerror(ret)) ?? "?"
            throw SocketsError(.ipAddressValidationFailed(reason))
        }
        
        guard let addrList = servinfo else { throw SocketsError(.ipAddressResolutionFailed) }
        defer {
            freeaddrinfo(addrList)
        }
        
        //this takes the first resolved address, potentially we should
        //get all of the addresses in the list and allow for iterative
        //connecting
        guard let addrInfo = addrList.pointee.ai_addr else { throw SocketsError(.ipAddressResolutionFailed) }
        let family = try AddressFamily(fromCType: Int32(addrInfo.pointee.sa_family))
        
        let ptr = UnsafeMutablePointer<sockaddr_storage>.allocate(capacity: 1)
        ptr.initialize(to: sockaddr_storage())
        
        switch family {
        case .inet:
            let addr = UnsafeMutablePointer<sockaddr_in>.init(OpaquePointer(addrInfo))!
            let specPtr = UnsafeMutablePointer<sockaddr_in>(OpaquePointer(ptr))
            specPtr.assign(from: addr, count: 1)
        case .inet6:
            let addr = UnsafeMutablePointer<sockaddr_in6>(OpaquePointer(addrInfo))!
            let specPtr = UnsafeMutablePointer<sockaddr_in6>(OpaquePointer(ptr))
            specPtr.assign(from: addr, count: 1)
        default:
            throw SocketsError(.concreteSocketAddressFamilyRequired)
        }
        
        let address = ResolvedInternetAddress(raw: ptr)
        
        // Adjust Config with the resolved address family
        config.addressFamily = try address.addressFamily()
        
        return address
    }
}
