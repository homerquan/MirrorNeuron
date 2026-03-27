package io.convospot.engine.actors.context

import akka.actor.{Actor, ActorContext, ActorLogging}
import io.convospot.engine.util.{ActorTrait, RedisConnector}

// TODO: using priority queue mailbox https://doc.akka.io/docs/akka/2.5/scala/mailboxes.html
private[convospot] class BotExceptionActor(bot:ActorContext) extends Actor with ActorTrait with ActorLogging {
  val redis=RedisConnector.getRedis
  def receive = {
    case _ => {
      log.error("unsupported message in " + this.getClass.getSimpleName)
      //output exp in exp-<bot_id> channel
    }
  }
}
