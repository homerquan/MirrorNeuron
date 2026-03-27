package io.convospot.engine.actors.conversation

import akka.actor.SupervisorStrategy.{Escalate, Restart, Resume}
import akka.actor._
import akka.pattern.ask
import akka.util.Timeout
import io.convospot.engine.actors.brain.PolicyActor
import io.convospot.engine.actors.context.BotOutputActor
import io.convospot.engine.actors.conversation.HelperActor.{Command, Data, State}
import io.convospot.engine.constants.Timeouts
import io.convospot.engine.grpc.data._

import scala.concurrent.Await
import scala.concurrent.duration.FiniteDuration
import io.convospot.engine.constants.Timeouts

/**
  * Augmented Intelligence from human and machine
  * Link to AI Brain
  * Switch mode: auto, semi, manual
  * Iu auto mode, AI answer directly
  * In semi mode, hear and ask AI, send best guess answer before timeout
  * In Manual mode, forward to the other party
  *
  * @param bot
  */
private[convospot] class HelperActor(bot: ActorContext, converation: ActorContext) extends FSM[HelperActor.State, HelperActor.Data] with ActorLogging {

  val machine = context.actorOf(Props(new PolicyActor(bot, converation)), "policy_actor")
  implicit val timeout = Timeout(Timeouts.MEDIAN)

  startWith(State.Semi, Data.Semi(Timeouts.MEDIAN, Set.empty[ActorRef]))

  when(State.Semi) {
    case Event(msg: SuperviseConversation, _) =>
      bot.child(msg.conversation).get ! ConversationActor.Command.Supervise()
      stay
    case Event(msg: UnsuperviseConversation, _) =>
      bot.child(msg.conversation).get ! ConversationActor.Command.Unsupervise()
      stay
    case Event(msg: Say,_) =>
      bot.child(msg.conversation).get ! ConversationActor.Command.Hear(self, "User", msg.message)
      stay
    case Event(msg: AddUserToHelper,stateData: Data.Semi) =>
      val newUser = bot.child(msg.user).get
      stay using stateData.copy(
        users = stateData.users + newUser
      )
    case Event(msg:Command.Hear,_) =>
      // TODO: Send to broadcast route. In timeout, if no human answer, forward the suggested result from brain.
      val future = machine ? PolicyActor.Command.Ask(msg.message)
      val result = Await.result(future, Timeouts.MEDIAN).asInstanceOf[Command.AnswerFromMachine]
      //TODO: DEMO ONLY
      sender ! ConversationActor.Command.Hear(self, "ai", result.message)
      stay
    case Event(msg: HelperActor.Message.Response,_) =>
      log.info(msg.toString)
      stay
    case Event(msg: SwitchHelperMode, stateData:Data.Semi) =>
      if (msg.mode == "auto")
        goto(State.Auto) using Data.Auto(Timeouts.MEDIAN, stateData.users)
      if (msg.mode == "manual")
        goto(State.Auto) using Data.Auto(Timeouts.MEDIAN, stateData.users)
      else
        stay

  }
  /**
    * Default handler
    */
  whenUnhandled {
    case Event(e, s) =>
      log.warning("received unhandled request {} in state {}/{}", e, stateName, s)
      stay
  }

  override val supervisorStrategy =
    OneForOneStrategy(maxNrOfRetries = 10, withinTimeRange = Timeouts.MEDIAN) {
      case _: ArithmeticException => Resume
      case _: NullPointerException => Restart
      case _: Exception => Escalate
    }

  override def preStart() {
    log.debug("A helper actor has created or recovered:" + self.path)
  }

  initialize()
}

private[convospot] object HelperActor {

  def props(bot: ActorContext, conversation: ActorContext) = Props(new HelperActor(bot,conversation))

  sealed trait Message

  object Message {

    final case class Response(message: String) extends Message

  }

  sealed trait Command

  object Command {

    final case class Hear(from: ActorRef, source: String, message: String) extends Command

    final case class AnswerFromMachine(message: String) extends Command

    final case class AnswerFromUser(message: String) extends Command

  }

  sealed trait Data

  object Data {

    final case class Manual(timeout: FiniteDuration, users: Set[ActorRef]) extends Data

    final case class Semi(timeout: FiniteDuration, users: Set[ActorRef]) extends Data

    final case class Auto(timeout: FiniteDuration, users: Set[ActorRef]) extends Data

  }


  sealed trait State

  object State {

    case object Auto extends State

    case object Semi extends State

    case object Manual extends State

  }

}