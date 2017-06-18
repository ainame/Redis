import Foundation

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
    var hostname: String { get }
    var port: Int16 { get }
}

protocol Client {
    func connect() throws
    func close() throws
}

protocol IO {
    var isSync: Bool { get set }
    
    func write(_ strings: String...) throws -> Int
    func read(max: Int) throws -> String
    func flush() throws
    func readLine() throws -> String
}

typealias TCPClient = Socket & Client & IO

class TemporaryClient: TCPClient {
    let hostname: String
    let port: Int16
    var isSync: Bool = false
    
    init(hostname: String, port: Int16) throws {
        self.hostname = hostname
        self.port = port
    }
    
    func connect() throws {
    }
    
    func close() throws {
    }
    
    func write(_ strings: String...) throws -> Int {
        return 1
    }
    
    func read(max: Int) throws -> String {
        return ""
    }
    
    func flush() throws {
    }
    
    func readLine() throws -> String {
        return ""
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
        client = try TemporaryClient(hostname: hostname, port: Int16(port))
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
        var wholeLine = try client.readLine()
        guard wholeLine.count != 0 else {
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
            
            let bulkString = try client.read(max: length)
            _ = try client.read(max: 2) // skip CR/LF
            
            return RedisValue.string(bulkString)
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
