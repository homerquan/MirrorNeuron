package io.convospot.engine.actors.context

import akka.actor.SupervisorStrategy.{Escalate, Restart, Resume}
import akka.actor._
import akka.persistence.SnapshotOffer
import io.convospot.engine.actors.brain.UserActor
import io.convospot.engine.actors.conversation.{ConversationActor, HelperActor, VisitorActor}
import io.convospot.engine.grpc.data.{CreateConversation, CreateHelper, CreateUser, CreateVisitor}
import io.convospot.engine.util.ActorTrait
import io.convospot.engine.constants.Timeouts

/**
  * The master actor for each bot
  * set context for each bot (multi-tenancy)
  * CQRS data flow into output and exception child actors
  */

private[convospot] class BotActor extends Actor with ActorTrait with ActorLogging {

  val outputActor=context.actorOf(Props(new BotOutputActor(context)),"outputActor")
  val exceptionActor=context.actorOf(Props(new BotExceptionActor(context)),"exceptionActor")

  //TODO: add unsubscribe later

  def receive = {
    case msg: CreateConversation => {
      context.actorOf(Props(new ConversationActor(context)),msg.id)
    }
    case msg: CreateVisitor => {
      context.actorOf(Props(new VisitorActor(context)),msg.id)
      sender ! "ok"
    }
// TODO: need create helper without conversation?
//    case msg: CreateHelper => {
//      context.actorOf(Props(new HelperActor(context)),msg.id)
//    }
    case msg: CreateUser => {
      context.actorOf(Props(new UserActor(context)),msg.id)
    }
    case _ =>log.error("unsupported message in " + this.getClass.getSimpleName)
  }

  override val supervisorStrategy =
    OneForOneStrategy(maxNrOfRetries = 10, withinTimeRange = Timeouts.MEDIAN) {
      case _: ArithmeticException => Resume
      case _: NullPointerException => Restart
      case _: Exception => Escalate
    }

  override def preStart() {
    log.debug("A bot actor has created or recovered:" + self.path)
  }
}