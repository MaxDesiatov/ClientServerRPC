//
//  main.swift
//
//
//  Created by Max Desiatov on 31/05/2022.
//

import ClientServerRPC
import Distributed

let s = RPCSystem()
let g = try Greeter.resolve(using: s)
try await g.hello()
