package io.convospot.engine.actors.conversation

import akka.actor._

import scala.collection.immutable
import akka.actor.SupervisorStrategy.{Escalate, Restart, Resume}
import akka.util.Timeout
import io.convospot.engine.actors.brain.PolicyActor
import io.convospot.engine.actors.context.output.{Action, ConversationUpdate, Intention}
import io.convospot.engine.actors.context.{BotOutputActor, ObserverActor}
import io.convospot.engine.actors.conversation.ConversationActor.{Command, Data, State}
import io.convospot.engine.constants.Timeouts
import io.convospot.engine.grpc.data.{Analytics, FillConversation}
import io.jvm.uuid.UUID

private[convospot] class ConversationActor(bot: ActorContext) extends FSM[ConversationActor.State, ConversationActor.Data] with ActorLogging {

  val observer = context.actorOf(Props(new ObserverActor(context)), "observer")

  /**
    * Initial state and data
    */
  startWith(State.Initial, Data.Initial)

  /**
    * State "Initial" handler
    *
    * @return
    */
  when(State.Initial) {

    case Event(msg: Command.Subscribe, _) =>
      sender ! VisitorActor.Message.Response(s"Join conversation ${this.getClass.getSimpleName}")
      // Only assign a helper once visitor is active
      // TODO: send "context" conversation to HelperActor as well
      val helper = bot.actorOf(Props(new HelperActor(bot, context)),UUID.random.toString)
      goto(State.Active) using Data.Active(Some(sender), Some(helper))
  }

  /**
    * State "Active" handler
    *
    * @return
    */
  when(State.Active) {

    case Event(msg: Command.Subscribe, stateData: Data.Active) =>
      sender ! VisitorActor.Message.Response(s"Re-join conversation ${this.getClass.getSimpleName}")
      stay using stateData.copy(
        visitor = Some(sender)
      )

    case Event(msg: Command.Leave, stateData: Data.Active) =>
      sender ! VisitorActor.Message.Response(s"Leave conversation ${this.getClass.getSimpleName}")
      stay using stateData.copy(
        visitor = None
      )

    case Event(msg: Command.Supervise, stateData: Data.Active) =>
      sender ! HelperActor.Message.Response(s"Supervise conversation ${this.getClass.getSimpleName}")
      stay using stateData.copy(
        helper = Some(sender)
      )
    case Event(msg: Command.Unsupervise, stateData: Data.Active) =>
      sender ! HelperActor.Message.Response(s"Stop supervise conversation ${this.getClass.getSimpleName}")
      stay using stateData.copy(
        helper = None
      )
    case Event(msg: Command.Hear, stateData: Data.Active) =>
      if (stateData.visitor!= None && msg.from == stateData.visitor.get && stateData.helper != None)
        stateData.helper.get ! HelperActor.Command.Hear.tupled(Command.Hear.unapply(msg).get)
      if (stateData.helper!= None && msg.from == stateData.helper.get && stateData.visitor != None)
        stateData.visitor.get ! VisitorActor.Command.Hear.tupled(Command.Hear.unapply(msg).get)
      stay

    /**
      * Unsubscribe visitor.
      */
    case Event(msg: Command.Leave, stateData: Data.Active) =>
      stay using stateData.copy(
        visitor = None
      )

    case Event(msg: Command.Unsupervise, stateData: Data.Active) =>
      stay using stateData.copy(
        helper = None
      )

    case Event(msg: FillConversation, stateData: Data.Active) =>
      val testData = ConversationUpdate(self.path.name,List(Intention("see",100)),List(Action("language","thinking","in-progress")))
      bot.child("outputActor").get ! BotOutputActor.Command.OutputConversationUpdate(self.path.name, testData)
      stay

    case Event(msg: Analytics, stateData: Data.Active) =>
      if(!stateData.visitor.isEmpty)
        stateData.visitor.get ! msg
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
    log.debug("A conversation actor has created or recovered:" + self.path)
  }

  initialize()
}

private[convospot] object ConversationActor {

  def props(bot: ActorContext) = Props(new ConversationActor(bot))

  sealed trait Command

  object Command {

    final case class Subscribe() extends Command

    final case class Leave() extends Command

    final case class Supervise() extends Command

    final case class Unsupervise() extends Command

    final case class Hear(from: ActorRef, source: String, message: String) extends Command

  }


  sealed trait Data

  object Data {

    case object Initial extends Data

    final case class Active(
                             visitor: Option[ActorRef],
                             helper: Option[ActorRef]
                           ) extends Data


  }


  sealed trait State

  object State {

    case object Initial extends State

    case object Active extends State


  }

}