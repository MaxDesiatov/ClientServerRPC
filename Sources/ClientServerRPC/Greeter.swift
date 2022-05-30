//
//  Greeter.swift
//
//
//  Created by Max Desiatov on 31/05/2022.
//

import Distributed

typealias DefaultDistributedActorSystem = RPCSystem

public distributed actor Greeter: DistributedSingleton {
  public distributed func hello() {
    print("Hello, Distributed World! My id is \(id)")
  }
}
