//
//  main.swift
//  Benchmark
//
//  Created by Satoshi Namai on 2017/06/17.
//

import Foundation
import Redis

let N: Int = 1000000
let start = Date()

let config = ConnectionConfiguration()
let redis = try! Redis(config)
let pipeline = redis.makePipeline()

let request = RedisValue.array([
    RedisValue.string("SET"),
    RedisValue.string("foo"),
    RedisValue.string("bar")
])

for _ in 1...N {
    _ = try! pipeline.command(request)
}
_ = try! pipeline.execute()

let timeInterval = Date().timeIntervalSince(start)
let throughput = Double(N) / timeInterval
print("Elapsed time: \(timeInterval), throughput: \(throughput) commands/sec")
print("Done")
