package io.convospot.engine.actors.brain

import akka.actor.SupervisorStrategy.{Escalate, Restart, Resume}
import akka.actor.{ActorContext, ActorLogging, FSM, OneForOneStrategy, Props}
import io.convospot.engine.constants.Timeouts
import io.convospot.engine.actors.brain.UserActor.{State,Data,Command}
/**
  *
  * A helper user
  * Demonstrates context.become FSM solution
  * context is representing the observed behavior
  *
  */
private[convospot] class UserActor(bot: ActorContext) extends FSM[UserActor.State, UserActor.Data] with ActorLogging {

  // TODO: Enable user actor (online, offline, message send thought it)
  startWith(State.Offline, Data.Offline())

  when(State.Offline) {
    case Event(msg:Command.Online,_) =>
      goto(State.Online) using Data.Online()
  }

  when(State.Online) {
    case Event(msg:Command.Offline,_) =>
      goto(State.Offline) using Data.Offline()
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

private[convospot] object UserActor {
  def props(bot: ActorContext) = Props(new UserActor(bot))

  sealed trait Message

  object Message {

    final case class Response(message: String) extends Message

  }

  sealed trait Command

  object Command {

    final case class Online() extends Command

    final case class Offline() extends Command

  }

  sealed trait Data

  object Data {

    final case class Online() extends Data

    final case class Offline() extends Data

  }


  sealed trait State

  object State {

    case object Online extends State

    case object Offline extends State

  }

}

