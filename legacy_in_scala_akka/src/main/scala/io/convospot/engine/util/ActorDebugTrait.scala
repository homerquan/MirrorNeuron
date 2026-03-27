package io.convospot.engine.util

import akka.actor.ActorSystem

private[convospot] trait ActorDebugTrait {
  def printActors(system:ActorSystem) = {
    val res = new PrivateMethodExposer(system)('printTree)()
    println(res)
  }
}
