//
//  RPCSystem.swift
//
//
//  Created by Max Desiatov on 30/05/2022.
//

import Distributed
@preconcurrency
import Foundation
import NIOCore

extension RemoteCallArgument: Codable {
  public init(from decoder: Decoder) throws {
    fatalError()
  }

  public func encode(to encoder: Encoder) throws {}
}

final class RPCSystem: DistributedActorSystem {
  typealias ActorID = String
  typealias SerializationRequirement = Codable

  enum SerializationError: Error {
    case unableToDecodeDataLength
    case unableToDecodeString
    case unableToSummonType
  }

  let encoder = JSONEncoder()
  let decoder = JSONDecoder()
  let underlyingTransport = Transport()

  func actorReady<Act>(_: Act) where Act: DistributedActor, ActorID == Act.ID {}

  func remoteCall<Act, Err, Res>(
    on actor: Act,
    target: RemoteCallTarget,
    invocation: inout InvocationEncoder,
    throwing _: Err.Type,
    returning _: Res.Type
  ) async throws -> Res
    where Act: DistributedActor, Act.ID == ActorID, Err: Error, Res: SerializationRequirement
  {
    var envelope = invocation.envelope

    // [1] the recipient is transferred over the wire as its id
    envelope.recipient = actor.id

    // [2] the method is a mangled identifier of the 'distributed func' (or var).
    //     In this system, we just use the mangled name, but we could do much better in the future.
    envelope.target = target.identifier

    // [3] send the envelope over the wire and await the reply:
    let responseData = try await underlyingTransport.send(envelope, to: actor.id)

    // [4] decode the response from the response bytes
    // in our example system, we're using Codable as SerializationRequirement,
    // so we can decode the response like this (and never need to cast `as? Codable` etc.):
    return try decoder.decode(Res.self, from: responseData)
  }

  func remoteCallVoid<Act, Err>(
    on actor: Act,
    target: RemoteCallTarget,
    invocation: inout InvocationEncoder,
    throwing: Err.Type
  ) async throws where Act: DistributedActor, Act.ID == ActorID, Err: Error {
    var envelope = invocation.envelope

    // [1] the recipient is transferred over the wire as its id
    envelope.recipient = actor.id

    // [2] the method is a mangled identifier of the 'distributed func' (or var).
    //     In this system, we just use the mangled name, but we could do much better in the future.
    envelope.target = target.identifier

    // [3] send the envelope over the wire and await the reply:
    try await underlyingTransport.send(envelope, to: actor.id)
  }

  func resolve<Act>(id: ActorID, as actorType: Act.Type) throws -> Act?
    where Act: DistributedActor, ActorID == Act.ID
  {
    nil
  }

  func assignID<Act>(_ actorType: Act.Type) -> ActorID
    where Act: DistributedActor, ActorID == Act.ID
  {
    ""
  }

  func resignID(_ id: ActorID) {}

  func makeInvocationEncoder() -> InvocationEncoder {
    .init(system: self)
  }
}

extension RPCSystem {
  func summonType(byName name: String) throws -> Any.Type {
    guard let type = _typeByName(name) else {
      throw SerializationError.unableToSummonType
    }

    return type
  }

  final class Transport: Sendable {
    @discardableResult
    func send(_ envelope: InvocationEncoder.Envelope, to actorID: ActorID) async throws -> Data {}
  }

  struct InvocationEncoder: DistributedTargetInvocationEncoder {
    typealias SerializationRequirement = RPCSystem.SerializationRequirement

    struct Envelope {
      var arguments = [Data]()
      var genericSubstitutions = [String]()
      var returnType: String?
      var errorType: String?
      var target: String?
      var recipient: String?
    }

    let system: RPCSystem
    var envelope: Envelope = .init()

    /// The arguments must be encoded order-preserving, and once `decodeGenericSubstitutions`
    /// is called, the substitutions must be returned in the same order in which they were recorded.
    mutating func recordGenericSubstitution<T>(_ type: T.Type) throws {
      // NOTE: we are showcasing a pretty simple implementation here...
      //       advanced systems could use mangled type names or registered type IDs.
      envelope.genericSubstitutions.append(String(reflecting: T.self))
    }

    mutating func recordArgument<Value: SerializationRequirement>(_ argument: RemoteCallArgument<Value>) throws {
      // in this implementation, we just encode the values one-by-one as we receive them:
      let argData = try system.encoder.encode(argument) // using whichever Encoder the system has configured
      envelope.arguments.append(argData)
    }

    mutating func recordErrorType<E: Error>(_ errorType: E.Type) throws {
      envelope.errorType = String(reflecting: errorType)
    }

    mutating func recordReturnType<R: SerializationRequirement>(_ returnType: R.Type) throws {
      envelope.returnType = String(reflecting: returnType)
    }

    /// Invoked when all the `record...` calls have been completed and the `DistributedTargetInvocation`
    /// will be passed off to the `remoteCall` to perform the remote call using this invocation representation.
    mutating func doneRecording() throws {
      // our impl does not need to do anything here
    }
  }

  struct InvocationDecoder: DistributedTargetInvocationDecoder {
    typealias SerializationRequirement = RPCSystem.SerializationRequirement

    let system: RPCSystem
    var bytes: ByteBuffer

    mutating func decodeGenericSubstitutions() throws -> [Any.Type] {
      guard let subCount: Int = bytes.readInteger() else {
        throw SerializationError.unableToDecodeDataLength
      }

      var subTypes: [Any.Type] = []
      for _ in 0..<subCount {
        // read the length of the next substitution
        guard
          let length: Int = bytes.readInteger(),
          let typeName = bytes.readString(length: length)
        else {
          continue
        }

        try subTypes.append(system.summonType(byName: typeName))
      }

      return subTypes
    }

    mutating func decodeNextArgument<Argument: SerializationRequirement>() throws -> Argument {
      guard
        let nextDataLength: Int = bytes.readInteger(),
        let nextData = bytes.readData(length: nextDataLength)
      else {
        throw SerializationError.unableToDecodeDataLength
      }

      // since we are guaranteed the values are Codable, so we can just invoke it:
      return try system.decoder.decode(Argument.self, from: nextData)
    }

    mutating func decodeErrorType() throws -> Any.Type? {
      // read the length of the type
      guard let length: Int = bytes.readInteger()
      else {
        throw SerializationError.unableToDecodeDataLength
      }

      guard length > 0 else {
        return nil // we don't always transmit it, 0 length means "none"
      }

      guard let typeName = bytes.readString(length: length) else {
        throw SerializationError.unableToDecodeString
      }
      return try system.summonType(byName: typeName)
    }

    mutating func decodeReturnType() throws -> Any.Type? {
      // read the length of the type
      guard let length: Int = bytes.readInteger()
      else {
        throw SerializationError.unableToDecodeDataLength
      }

      guard length > 0 else {
        return nil // we don't always transmit it, 0 length means "none"
      }

      guard let typeName = bytes.readString(length: length) else {
        throw SerializationError.unableToDecodeString
      }
      return try system.summonType(byName: typeName)
    }
  }

  struct ResultHandler: DistributedTargetInvocationResultHandler {
    typealias SerializationRequirement = RPCSystem.SerializationRequirement

    func onReturnVoid() async throws {}
    func onThrow<Err>(error: Err) async throws where Err: Error {}

    mutating func onReturn<Success: SerializationRequirement>(value: Success) async throws {}
  }
}
