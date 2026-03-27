package io.convospot.engine.actors.brain

import akka.actor.SupervisorStrategy.{Escalate, Restart, Resume}
import akka.actor.{Actor, ActorContext, ActorLogging, OneForOneStrategy}
import io.convospot.engine.constants.GrpcOutputCode.GET_KNOWLEDGE
import io.convospot.engine.grpc.output.{Request, Response}
import io.convospot.engine.util.GrpcApiConnector
import spray.json._
import com.softwaremill.sttp._
import io.convospot.engine.constants.Timeouts


private[convospot] class KnowledgeActor(bot:ActorContext) extends Actor with ActorLogging{

  def receive = {
    case KnowledgeActor.Command.Ask(message: String) =>
      val request = Request(typeCode = GET_KNOWLEDGE, data = bot.self.path.name)
      val reply: Response = GrpcApiConnector.blockingStub.ask(request)
      val kb = reply.data
      sender ! PolicyActor.Command.AnswerFromKnowledge(getAnswer(kb,message))
    case KnowledgeActor.Command.Learn(message: String) =>
        //TODO: improve language understanding mode
    case _ => log.error("unsupported message in " + this.getClass.getSimpleName)
  }

  private def getAnswer(passage:String, question: String): String = {

    val request = sttp
        .header("Content-Type", "application/json")
        .header("Accept", "application/json")
        .post(uri"http://10.0.1.100:8000/predict/machine-comprehension")
        .body(s"""{"passage":"${passage}","question":"${question}"}""")

    implicit val backend = HttpURLConnectionBackend()
    val response = request.send()

    log.info(request.toString)
    log.info(response.toString)

    // TODO: add exception handler
    // response.header(...): Option[String]
    println(response.header("Content-Length"))

    // response.unsafeBody: by default read into a String
    response.unsafeBody.parseJson.asJsObject.getFields("best_span_str")(0).toString()

  }

  override val supervisorStrategy =
    OneForOneStrategy(maxNrOfRetries = 10, withinTimeRange = Timeouts.MEDIAN) {
      case _: ArithmeticException => Resume
      case _: NullPointerException => Restart
      case _: Exception => Escalate
    }
}

object KnowledgeActor {

  object Command {
    final case class Ask(message: String)
    final case class Learn(reply: String)
  }

}