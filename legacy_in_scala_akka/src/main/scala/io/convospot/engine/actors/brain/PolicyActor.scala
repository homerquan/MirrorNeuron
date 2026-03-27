package io.convospot.engine.actors.brain

import akka.actor.SupervisorStrategy.{Escalate, Restart, Resume}
import akka.actor._
import akka.pattern.ask
import akka.util.Timeout

import scala.concurrent.duration._
import scala.concurrent.Await
import io.convospot.engine.actors.brain.PolicyActor.Command
import io.convospot.engine.actors.conversation.HelperActor
import io.convospot.engine.constants.GrpcOutputCode.SUGGEST_RESPONSE
import io.convospot.engine.constants.Timeouts
import spray.json._
import io.convospot.engine.grpc.data.JsonProtocol._
import io.convospot.engine.grpc.data._
import io.convospot.engine.grpc.output.{Request, Response}
import io.convospot.engine.util.GrpcConsoleApiConnector
import io.convospot.engine.actors.brain.PolicyActor.{Command, Data, State}

case object AskNameMessage

private[convospot] class PolicyActor(bot: ActorContext, conversation: ActorContext) extends FSM[PolicyActor.State, PolicyActor.Data] with ActorLogging {

  implicit private val timeout = Timeout(Timeouts.MEDIAN)
  val languageActor = context.actorOf(Props(new LanguageActor(bot)), "language_actor")
  val knowledgeActor = context.actorOf(Props(new KnowledgeActor(bot)), "knowledge_actor")
  val defaultWaiting = 10
  val conversationId = conversation.self.path.name
  val botId = bot.self.path.name

  startWith(State.Normal, Data.Normal())

  when(State.Normal) {
    case Event(msg: Command.Ask, _) =>
      //TODO: only trying to understand language here, it should go KB and Action later
      //Using route here
      val future = knowledgeActor ? KnowledgeActor.Command.Ask(msg.message)
      val result = Await.result(future, Timeouts.MEDIAN).asInstanceOf[Command.AnswerFromKnowledge]
      val text = result.message.stripPrefix("\"").stripSuffix("\"").trim
      // demo knowledge only, Wait for semi auto mode (TODO: temp solution, MVP semi auto only)
      // TODO: add timeout handler
      val requestId = java.util.UUID.randomUUID.toString
      val request = Request(typeCode = SUGGEST_RESPONSE, data = KnowledgeSuggestion(requestId, text, conversationId, defaultWaiting).toJson.toString())
      val reply: Response = GrpcConsoleApiConnector.blockingStub.ask(request) //TODO: if not ok, handle error
      // wait until console user take action
      // sender ! HelperActor.Command.AnswerFromMachine(text)
      goto(State.Waiting) using Data.Waiting(defaultWaiting, text, sender, requestId)

  }

  when(State.Waiting, stateTimeout = defaultWaiting second) {
    case Event(StateTimeout, stateData: Data.Waiting) =>
      // TODO: if manual, cancel waiting
      stateData.originSender ! HelperActor.Command.AnswerFromMachine(stateData.text)
      goto(State.Normal)
    case Event(msg: Command.Accept, stateData:Data.Waiting) =>
      //TODO: match id (or even has a queue of multi waiting requests)
      stateData.originSender ! HelperActor.Command.AnswerFromMachine(stateData.text)
      goto(State.Normal)
    case Event(msg: Command.Ignore, stateData:Data.Waiting) =>
      goto(State.Normal)
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
    log.debug("A visitor actor has created or recovered:" + self.path)
  }

  initialize()
}

object PolicyActor {

  def props(bot: ActorContext,conversation: ActorContext) = Props(new PolicyActor(bot,conversation))

  sealed trait Command

  object Command {

    final case class Ask(message: String) extends Command

    final case class Learn(context: String) extends Command

    final case class AnswerFromKnowledge(message: String) extends Command

    final case class Accept(id: String) extends Command

    final case class Ignore(id: String) extends Command

  }

  sealed trait Data

  object Data {

    final case class Normal() extends Data

    final case class Waiting(delay: Int, text: String, originSender: ActorRef, id: String) extends Data

  }


  sealed trait State

  object State {

    case object Normal extends State

    case object Waiting extends State

  }

}