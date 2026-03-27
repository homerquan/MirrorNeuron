package io.convospot.engine.config
import com.typesafe.config.ConfigFactory


/**
  * SCALA config for environments: development, stage, production
  */
private[convospot] object Config {
  val env = if (System.getenv("SCALA_ENV") == null) "development" else System.getenv("SCALA_ENV")
  val conf = ConfigFactory.load()
  def apply() = conf.getConfig(env)
  def parse(path:String) =  ConfigFactory.parseString(path).
    withFallback(conf.getConfig(env))
}
