package io.convospot.engine.actors.brain

import org.specs2.Specification
import io.convospot.engine.util.ActorsTestSupport
import scala.concurrent.duration._
import akka.testkit.TestProbe
import akka.actor.Props

class KnowledgeActorSpec extends Specification {
  def is = sequential ^ s2"""
    A knowledge Actor have to
    can get answer                             getAnswer
    """

  def getAnswer = {
    new ActorsTestSupport {
      within(1 second) {
        val probe = TestProbe()
        val message = KnowledgeActor.Command.Ask("what is your vision?")
        val actor = system.actorOf(Props(classOf[KnowledgeActor]))
        actor.tell(message, probe.ref)
        probe.expectMsgType[String]
      }
    }
  }
}
