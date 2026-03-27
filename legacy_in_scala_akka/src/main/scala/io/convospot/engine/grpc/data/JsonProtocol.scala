package io.convospot.engine.grpc.data

import spray.json.{DefaultJsonProtocol}


/**
  * JsonProtocol for parse & stringify json objects
  */

private[convospot] object JsonProtocol extends DefaultJsonProtocol {
  implicit val createBotFormat = jsonFormat(CreateBot, "id", "client")
  implicit val createVisitorFormat =  jsonFormat(CreateVisitor, "id", "bot", "client")
  implicit val createHelperFormat =  jsonFormat(CreateHelper, "id", "bot", "client")
  implicit val createConversationFormat = jsonFormat(CreateConversation, "id", "bot", "client")
  implicit val joinConversationFormat = jsonFormat(JoinConversation, "visitor", "conversation", "bot", "client")
  implicit val leaveConversationFormat = jsonFormat(LeaveConversation, "visitor", "conversation", "bot", "client")
  implicit val superviseConversationFormat = jsonFormat(SuperviseConversation, "helper", "conversation", "bot", "client")
  implicit val unsuperviseConversationFormat = jsonFormat(UnsuperviseConversation, "helper", "conversation", "bot", "client")
  implicit val sayFormat = jsonFormat(Say, "source", "sid", "message", "conversation", "bot", "client")
  implicit val switchHelperModeFormat = jsonFormat(SwitchHelperMode, "conversation", "mode","bot", "client")
  implicit val onlineVisitorFormat = jsonFormat(OnlineVisitor,"visitor","bot","client")
  implicit val offlineVisitorFormat = jsonFormat(OfflineVisitor,"visitor","bot","client")
  implicit val createUserFormat = jsonFormat(CreateUser, "id", "bot", "client")
  implicit val onlineUserFormat = jsonFormat(OnlineUser,"user","bot","client")
  implicit val offlineUserFormat = jsonFormat(OfflineUser,"user","bot","client")
  implicit val addUserToHelperFormat = jsonFormat(AddUserToHelper,"user","helper","bot","client")
  implicit val fillConversationFormat = jsonFormat(FillConversation,"conversation","bot","client")
  implicit val analyticsFormat = jsonFormat(Analytics,"eid","visitor","conversation","bot","event","intention","timestamp")
  implicit val botFormat = jsonFormat(Bot, "id","client")
  implicit val visitorFormat = jsonFormat(Visitor, "id", "bot", "client")
  implicit val conversationFormat = jsonFormat(Conversation, "id","visitor","mode","status","bot","client")
  implicit val knowledgeSuggestionFormat = jsonFormat(KnowledgeSuggestion, "id","text","conversation","delay")
}
