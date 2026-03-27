package io.convospot.engine.actors.brain

import akka.actor._

private[convospot] class LanguageActor(bot:ActorContext) extends Actor with ActorLogging {

  def receive = active(scala.collection.mutable.Map.empty[String, String])

  def active(memory: scala.collection.mutable.Map[String, String]): Receive = {
    case LanguageActor.Message.Ask(message: String) =>
      val reply = memory.getOrElse(message, "")
      log.info("memory is {}", memory.toString())
//      if (reply == "")
//        sender ! Messages.Acknowledge("AI has no answer")
//      else
//        sender ! Messages.Utterance(reply, "ai", "visitor") //Know nothing is a Acknowledge not utterrance
    case LanguageActor.Message.Learn(conversation: String, reply: String) =>
      context become active(memory += (conversation -> reply))
      //Add this sentence into knowledge
      if(reply.length>20) {
       // context.actorSelection("../sample_knowledge_actor")!KnowledgeActor.Message.Learn(reply)
      }
    case _ => log.error("unsupported message in " + this.getClass.getSimpleName)
  }

}

object LanguageActor {

  object Command {

  }

  object Message {

    final case class Ask(message: String) //TODO: add room context
    final case class Learn(conversation: String, reply: String)

  }

}