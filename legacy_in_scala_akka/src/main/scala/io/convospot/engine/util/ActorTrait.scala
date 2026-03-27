package io.convospot.engine.util
import akka.actor.{ActorContext, ActorRef}

private[convospot] trait ActorTrait {
  def findChildByName(name: String, context: ActorContext): Option[ActorRef] = context.child(name)
}

