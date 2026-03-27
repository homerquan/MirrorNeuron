# Mirrorneuron Engine

A real-time decision engine

## Todo

Recover from restart

## How to run

Run CEP:
sbt run

Test CEP:
sbt test


Package into a jar (include deps):
sbt assembly

Run an interactive console(REPL):
sbt "run -c"

* telnet localhost 1981
* telnet localhost 1982

Branches:

stage_release -> dev build
prod_release -> rc build

Note:
Remember to highlight protobuf folder as source code
After change proto, run: `sbt compile`

## Requirement

Redis: ``docker run --name convospot-redis -d redis``
alennlp: ``docker run -p 8000:8000 -d allennlp/allennlp``

## Development setting

* Intellij 2017+
* Intellij Scala plugin
* [Intellij Protobuf plugin](https://plugins.jetbrains.com/plugin/8277-protobuf-support)
* Scala Protobuf compiler https://scalapb.github.io/grpc.html

## Debug

* Visulize actor system: http://localhost:8888
    * https://github.com/blstream/akka-viz

## GRPC in scala

* https://www.beyondthelines.net/computing/grpc-in-scala/

## GRPC Stream with AKKA

https://www.beyondthelines.net/computing/grpc-akka-stream/

## Call GRPC in nodejs

```
npm install -g grpc-tools
grpc_tools_node_protoc --js_out=import_style=commonjs,binary:../node/static_codegen/ --grpc_out=../node/static_codegen --plugin=protoc-gen-grpc=`which grpc_tools_node_protoc_plugin` helloworld.proto
```

Check details at https://grpc.io/docs/quickstart/node.html

## Converstaion FSM

``State(S) x Event(E) -> Actions (A), State(S’)``

## Reference

AKKA Docs: https://doc.akka.io/docs/akka/2.5.6/scala/
Scala CLI opt parser: https://github.com/scopt/scopt
grpc in scala: https://www.beyondthelines.net/computing/grpc-in-scala/
grpc to akka handler: https://github.com/eiennohito/grpc-akka-stream-subrepo
Using stream for event processing https://index.scala-lang.org/qubitproducts/akka-cloudpubsub/akka-cloudpubsub/1.0.0?target=_2.11
Vis for debug https://github.com/blstream/akka-viz