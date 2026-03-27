package io.convospot.engine.grpc

import akka.actor.ActorSystem
import io.convospot.engine.grpc.input.{CommandsGrpc, Request, Response}
import io.grpc.stub.StreamObserver

import scala.concurrent.Future

private[convospot] class ConversationImpl(system:ActorSystem) extends CommandsGrpc.Commands {
  private val executoer = new GrpcExecutor(system)

  override def say(req: Request) = {
    val reply = Response(message = "Hello " + req.message)
    Future.successful(reply)
  }

  /*
   * @param responseObserver an observer to receive the stream of previous messages.
   * @return an observer to handle requested message/location pairs.
   */
  override def stream(responseObserver: StreamObserver[Response]): StreamObserver[Request] = {
    new StreamObserver[Request]() {
      override def onNext(note: Request): Unit = {
      }

      override def onError(t: Throwable): Unit = {
      }

      override def onCompleted(): Unit = {
        responseObserver.onCompleted
      }
    }
  }

  override def ask(req: Request) = executoer.handlers(req: Request)
}
