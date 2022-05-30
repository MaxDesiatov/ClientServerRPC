import ClientServerRPC
import Vapor

func routes(_ app: Application) throws {
  app.get { _ in
    "It works!"
  }

  app.get("hello") { _ -> String in
    let s = RPCSystem()
    return "Hello, world!"
  }
}
