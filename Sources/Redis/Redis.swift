import Foundation
import Libc

public struct ConnectionConfiguration {
    var hostname: String = "localhost"
    var port: Int = 6379
    var password: String? = nil
    
    public init() {}
}

public enum RedisValue {
    case null
    case int(Int64)
    case string(String)
    indirect case array(Array<RedisValue>)
}

public typealias Request = RedisValue

public enum RedisError: Error {
    case errorResponse
    case invalidSequnece
    case disconnectedError
}

public class Redis: RedisCommandExecutable {
    let config: ConnectionConfiguration
    let connection: Connection

    public init(_ config: ConnectionConfiguration) throws {
        self.config = config
        self.connection = try Connection(hostname: config.hostname, port: config.port)
    }
    
    public func makePipeline() -> RedisPipeline {
        return RedisPipeline(connection)
    }
}

public class RedisPipeline: RedisCommandExecutable {
    let connection: Connection
    var enqueuedCount: Int = 0
    
    init(_ connection: Connection) {
        self.connection = connection
    }
    
    public func command(_ request: Request) throws -> RedisValue {
        try connection.queue(request)
        enqueuedCount += 1
        return RedisValue.null
    }
    
    public func execute() throws {
        try connection.flush()
        var array = [RedisValue]()
        for _ in 0..<enqueuedCount {
            array.append(try connection.receive())
        }
    }
}

protocol RedisCommandExecutable {
    var connection: Connection { get }
    func command(_ request: Request) throws -> RedisValue
}

extension RedisCommandExecutable {
    func command(_ request: Request) throws -> RedisValue {
        try connection.send(request)
        return try connection.receive()
    }
    
    public func set(_ key: String, _ value: String) throws -> String? {
        let request = RedisValue.array([
            RedisValue.string("SET"),
            RedisValue.string(key),
            RedisValue.string(value)
            ])
        
        let response = try command(request)
        if case .string(let responseValue) = response {
            return responseValue
        }
        return nil
    }
    
    public func get(_ key: String) throws -> String? {
        let request = RedisValue.array([
            RedisValue.string("GET"),
            RedisValue.string(key),
            ])
        try connection.send(request)
        let response = try connection.receive()
        
        if case .string(let responseValue) = response {
            return responseValue
        }
        return nil
    }
}

protocol Socket {
    var descriptor: Descriptor { get set }
}

protocol Client {
    func connect() throws
    func close() throws
}

protocol IO {
    var isSync: Bool { get set }
    
    func write(_ strings: String...) throws -> Int
    func read(max: Int) throws -> String?
    func flush() throws
    func readLine() throws -> String?
}

typealias TCPClient = Socket & Client & IO

class TemporaryClient: TCPClient {
    let hostname: String
    let port: Int
    var isSync: Bool = false
    var descriptor: Descriptor
    
    private let internetAddress: InternetAddress
    private let address: ResolvedInternetAddress
    private var writeBuffer = [UInt8]()
    private var readBuffer = [UInt8]()
    
    init(hostname: String, port: Int) throws {
        self.hostname = hostname
        self.port = port
        
        internetAddress = InternetAddress(hostname: hostname, port: Port(port))
        var conf = Config.TCP(addressFamily: internetAddress.addressFamily)
        address = try internetAddress.resolve(with: &conf)
        descriptor = try Descriptor(conf)
    }
    
    func connect() throws {
        let res = Libc.connect(descriptor.raw, address.raw, address.rawLen)
        if res < 0 {
            throw SocketsError(.connectFailed(scheme: "http", hostname: internetAddress.hostname, port: internetAddress.port))
        }
    }
    
    func close() throws {
        if Libc.close(descriptor.raw) != 0 {
            if errno == EBADF {
                descriptor = -1
                throw SocketsError(.socketIsClosed)
            } else {
                throw SocketsError(.closeSocketFailed)
            }
        }
        
        // set descriptor to -1 to prevent further use
        descriptor = -1
    }
    
    func write(_ strings: String...) throws -> Int {
        let before = writeBuffer.count
        for string in strings {
            writeBuffer.append(contentsOf: string.utf8)
        }
        return writeBuffer.count - before
    }
    
    func flush() throws {
        let bytesWritten = Libc.send(descriptor.raw, writeBuffer, writeBuffer.count, 0)
        print("flash: \(bytesWritten)")
        guard bytesWritten != -1 else {
            switch errno {
            case EINTR:
                // try again
                return try flush()
            case ECONNRESET:
                // closed by peer, need to close this side.
                // Since this is not an error, no need to throw unless the close
                // itself throws an error.
                _ = try self.close()
                return
            default:
                throw SocketsError(.writeFailed)
            }
        }
        writeBuffer.removeAll()
    }
    
    static let readBufferMaxSize: Int = 8192
    func read(max: Int) throws -> String? {
        print("read")
        
        if max <= readBuffer.count {
            let readed = String(bytes: readBuffer[0...max], encoding: .utf8)
            _ = readBuffer.dropFirst(max)
            return readed
        }
        let receivedBytes = Libc.read(descriptor.raw, &readBuffer, max)
        guard receivedBytes != -1 else {
            switch errno {
            case EINTR:
                // try again
                return try read(max: max)
            case ECONNRESET:
                // closed by peer, need to close this side.
                // Since this is not an error, no need to throw unless the close
                // itself throws an error.
                _ = try self.close()
                throw SocketsError(.readFailed)
            case EAGAIN:
                // timeout reached (linux)
                throw SocketsError(.readFailed)
            default:
                throw SocketsError(.readFailed)
            }
        }
        
        guard receivedBytes > 0 else {
            // receiving 0 indicates a proper close .. no error.
            // attempt a close, no failure possible because throw indicates already closed
            // if already closed, no issue.
            // do NOT propogate as error
            _ = try? self.close()
            throw SocketsError(.readFailed)
        }
        
        let toRead = [receivedBytes, max].min()!
        let readed = String(bytes: readBuffer[0...toRead], encoding: .utf8)
        _ = readBuffer.dropFirst(toRead)
        return readed
    }
    
    func readLine() throws -> String? {
        print("readline")
        if let index = findBreakline() {
            print("finded!")
            return String(bytes: readBuffer.dropFirst(index), encoding: .utf8)!
        }
        
        print("@1")
        
        while true {
            let receivedBytes = Libc.read(descriptor.raw, &readBuffer, TemporaryClient.readBufferMaxSize)
            print("receivedBytes: \(receivedBytes), buf:\(readBuffer)")
            print("@2")
            
            guard receivedBytes != -1 else {
                print("@errno\(errno)")
                
                switch errno {
                case EINTR:
                    // try again
                    print("try again")
                    return try readLine()
                case ECONNRESET:
                    // closed by peer, need to close this side.
                    // Since this is not an error, no need to throw unless the close
                    // itself throws an error.
                    _ = try self.close()
                    if readBuffer.isEmpty {
                        return nil
                    } else {
                        let readed = String(bytes: readBuffer, encoding: .utf8)
                        readBuffer.removeAll()
                        return readed
                    }
                case EAGAIN:
                    // timeout reached (linux)
                    if readBuffer.isEmpty {
                        return nil
                    } else {
                        let readed = String(bytes: readBuffer, encoding: .utf8)
                        readBuffer.removeAll()
                        return readed
                    }
                default:
                    throw SocketsError(.readFailed)
                }
            }
            
            guard receivedBytes > 0 else {
                _ = try? self.close()
                let readed = String(bytes: readBuffer, encoding: .utf8)
                readBuffer.removeAll()
                return readed
            }
            
            print("find breakline")
            if let index = findBreakline() {
                return String(bytes: readBuffer.dropFirst(index), encoding: .utf8)!
            }
        }
    }
    
    private func findBreakline() -> Int? {
        let codeOfBreakline = Int8(("\n" as UnicodeScalar).value)
        print("\(readBuffer)")
        for (index, char) in readBuffer.enumerated() {
            print("\n\(codeOfBreakline), char: \(char)")
            if codeOfBreakline == char {
                return index
            }
        }
        return nil
    }
}

class Connection {
    enum State {
        case notConnected
        case connected
        case error
    }

    private(set) var state: State = .notConnected
    private let client: TCPClient
    
    init(hostname: String, port: Int) throws {
        client = try TemporaryClient(hostname: hostname, port: port)
        do {
            try client.connect()
            state = .connected
        } catch {
            state = .notConnected
        }
    }
    
    func queue(_ request: Request) throws {
        switch request {
        case .array(let array):
            try marshal(array: array, into: client)
        case .int(let int):
            try marshal(int: int, into: client)
        case .string(let string):
            try marshal(string: string, into: client)
        case .null:
            try marshalWithNil(into: client)
        }
    }

    func send(_ request: Request) throws {
        try queue(request)
        try flush()
    }
    
    func flush() throws {
        try client.flush()
    }
    
    func receive() throws -> RedisValue {
        print("receive")
        guard let _wholeLine = try client.readLine() else {
            throw RedisError.invalidSequnece
        }
        print("whole: \(_wholeLine)")
        var wholeLine = _wholeLine
        if wholeLine.count == 0 {
            throw RedisError.disconnectedError
        }
        
        let type = wholeLine.prefix(1)
        wholeLine.removeFirst()
        let line = wholeLine
        switch type {
        case "-":
            // error
            throw RedisError.errorResponse
        case ":":
            // integer
            return RedisValue.int(Int64(line)!)
        case "$":
            // bulk string
            let length = Int(line)!
            guard length != -1 else { return RedisValue.null }
            
            if let bulkString = try client.read(max: length) {
                _ = try client.read(max: 2) // skip CR/LF
                return RedisValue.string(bulkString)
            } else {
                fatalError("invalid data")
            }
        case "+":
            // simple string
            return RedisValue.string(line)
        case "*":
            let length = Int(line)!
            var array = [RedisValue]()
            for _ in 0..<length {
                array.append(try receive())
            }
            return RedisValue.array(array)
        default:
            throw RedisError.invalidSequnece
        }
    }

    func close() throws {
        guard state == .connected else {
            return
        }

        try client.close()
        state = .notConnected
    }
    
    func marshal(array: Array<RedisValue>, into io: TCPClient) throws {
        _ = try io.write("*", String(array.count), "\r\n")
        for element in array {
            switch element {
            case .array(let array):
                try marshal(array: array, into: io)
            case .int(let int):
                try marshal(int: int, into: io)
            case .string(let string):
                try marshal(string: string, into: io)
            case .null:
                try marshalWithNil(into: io)
            }
        }
    }
    
    func marshal(int: Int64, into io: TCPClient) throws {
        _ = try io.write(":", String(int), "\r\n")
    }
    
    func marshal(string: String, into io: TCPClient) throws {
        _ = try io.write("$", String(string.lengthOfBytes(using: String.Encoding.utf8)), "\r\n", string, "\r\n")
    }
    
    func marshalWithNil(into io: TCPClient) throws {
        _ = try io.write("$-1\r\n")
    }
    
    static let bytesPerQueuedResponses = "+QUEUED\r\n".lengthOfBytes(using: .utf8)
    
    func receiveQueuedResponses(_ numberOfQueued: Int) throws {
        guard numberOfQueued != 0 else {
            return
        }
        
        let byteLength = numberOfQueued * Connection.bytesPerQueuedResponses
        _ = try client.read(max: byteLength)
    }
}
