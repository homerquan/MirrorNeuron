package io.convospot.engine.grpc

import akka.actor.ActorSystem

import scala.concurrent.{ExecutionContext, Future}
import io.grpc.ServerBuilder
import io.convospot.engine.grpc.input.CommandsGrpc
import io.convospot.engine.constants.GrpcOutputCode
import io.convospot.engine.grpc.GrpcExecutor
import org.apache.log4j._
import io.convospot.engine.util.CommonTrait


private[convospot] object GrpcLauncher extends CommonTrait {
  private implicit val system = ActorSystem("convospot-engine")

  val server = new GrpcServer(
    ServerBuilder
      .forPort(config.getInt("grpc.port"))
      .addService(CommandsGrpc.bindService(new ConversationImpl(system), ExecutionContext.global))
      .build()
  )

  def start() = {
    // restore actors from persistent storage
    val systemRestore = new SystemRecovery(system)
    systemRestore.restore()

    // TODO if success, change ready status
    log.debug("Grpc server is ready.")
    server.start()
    server.blockUntilShutdown()
  }

}
