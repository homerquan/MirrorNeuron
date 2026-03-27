package io.convospot.engine.actors.context.output

/**
 * Json for output
 */
final case class CreateMessage(helper: String, source: String, text: String, conversation: String, visitor: String)
final case class Intention(name:String,score:Int)
final case class Action(source:String,name:String,status:String)
final case class ConversationUpdate(id: String, intentions: List[Intention], actions: List[Action])
final case class ConversationIntentionsUpdate(id: String, intentions: List[Intention])
final case class ConversationActionsUpdate(id: String, actions: List[Action])