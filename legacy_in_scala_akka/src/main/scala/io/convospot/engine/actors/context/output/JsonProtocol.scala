package io.convospot.engine.actors.context.output

import spray.json.DefaultJsonProtocol

private[convospot] object JsonProtocol extends DefaultJsonProtocol {
  implicit val createMessageFormat = jsonFormat(CreateMessage, "helper", "source", "text", "conversation", "visitor")
  implicit val intentionFormat = jsonFormat(Intention,"name","score")
  implicit val actionFormat = jsonFormat(Action,"source","name","status")
  implicit val conversationUpdateFormat = jsonFormat(ConversationUpdate,"id","intentions","actions")
  implicit val conversationIntentionsUpdateFormat = jsonFormat(ConversationIntentionsUpdate,"id","intentions")
  implicit val conversationActionsUpdateFormat = jsonFormat(ConversationActionsUpdate,"id","actions")
}