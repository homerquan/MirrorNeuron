name := "engine"

organization := "io.convospot"

version := "0.2.0"

scalaVersion := "2.11.11"

fork := true

resolvers ++= Seq(
  "Typesafe Repo" at "http://repo.typesafe.com/typesafe/releases/",
  Resolver.jcenterRepo
)

libraryDependencies ++= Seq(
  "com.typesafe.akka" %% "akka-actor" % "2.5.6",
  "com.typesafe.akka" %% "akka-contrib" % "2.5.6",
  "com.typesafe.akka" %% "akka-testkit" % "2.5.6",
  "com.typesafe.akka" %% "akka-stream" % "2.5.6",
  "com.typesafe.akka" %% "akka-cluster" % "2.5.6",
  "com.typesafe.akka" %% "akka-cluster-sharding" % "2.5.6",
  "io.spray" %% "spray-json" % "1.3.1",
  "io.spray" %% "spray-client" % "1.3.1",
  "io.spray" %% "spray-httpx" % "1.3.1",
  "io.spray" %% "spray-routing" % "1.3.1",
  "com.softwaremill.sttp" %% "core" % "1.1.2",
  "org.iq80.leveldb" % "leveldb" % "0.9",
  "org.scalaz" %% "scalaz-core" % "7.2.15",
  "org.specs2" %% "specs2-core" % "4.0.0" % "test",
  "com.typesafe.scala-logging" %% "scala-logging" % "3.7.2",
  "org.slf4j" % "slf4j-api" % "1.7.25",
  "org.slf4j" % "log4j-over-slf4j" % "1.7.25",
  "ch.qos.logback" % "logback-classic" % "1.2.3",
  "com.github.scopt" %% "scopt" % "3.7.0",
  "net.debasishg" %% "redisclient" % "3.4",
  "org.specs2" %% "specs2-core" % "4.0.0",
  "io.jvm.uuid" %% "scala-uuid" % "0.2.3",
  "com.github.scullxbones" %% "akka-persistence-mongo-rxmongo" % "2.0.4",
  "io.grpc" % "grpc-netty" % com.trueaccord.scalapb.compiler.Version.grpcJavaVersion,
  "com.trueaccord.scalapb" %% "scalapb-runtime-grpc" % com.trueaccord.scalapb.compiler.Version.scalapbVersion
)

scalacOptions in Test ++= Seq("-Yrangepos")

mainClass in Compile := Some("io.convospot.engine.app.Main")

PB.targets in Compile := Seq(
  scalapb.gen() -> (sourceManaged in Compile).value
)

assemblyMergeStrategy in assembly := {
  case PathList("META-INF", xs @ _*) => MergeStrategy.discard
  case x => MergeStrategy.first
}