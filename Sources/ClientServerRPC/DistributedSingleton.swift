//
//  Created by Max Desiatov on 31/05/2022.
//

import Distributed

public protocol DistributedSingleton: DistributedActor where ID == String {}

public extension DistributedSingleton {
  static var singletonID: String { String(reflecting: Self.self) }

  static func resolve(using system: Self.ActorSystem) throws -> Self {
    try Self.resolve(id: Self.singletonID, using: system)
  }
}
