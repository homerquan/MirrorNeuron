package io.convospot.engine.util

import akka.actor.ActorSystem
import akka.testkit.{ImplicitSender, TestKit}
import org.specs2.mutable.After
import org.specs2.specification.Scope

/**
  * a Specs2 'context' for akka.testkit
  * Created by homer on 4/30/15.
  */

abstract class ActorsTestSupport extends TestKit(ActorSystem("engine-test"))
  with Scope
  with After
  with ImplicitSender {
  // make sure we shut down the actor system after all tests have run
  def after = TestKit.shutdownActorSystem(system)
}