package io.convospot.engine.util

import com.redis.{RedisClientPool, RedisClient}
import io.convospot.engine.config.Config

private[convospot] object RedisConnector {
  private val config =Config.apply()
  private val redisHost = config.getString("redis.host")
  private val redisPort=config.getInt("redis.port")
  private val clientPool = new RedisClientPool(redisHost, redisPort)
  // [important] use separate connections for each actor
  def getRedis () = {
    new RedisClient(redisHost, redisPort)
  }
  def getPool () = clientPool
}