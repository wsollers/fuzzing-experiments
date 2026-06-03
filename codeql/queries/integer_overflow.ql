/**
 * @name Integer overflow / wraparound paths
 * @description Finds arithmetic on values derived from external input that
 *              could overflow before being used as buffer sizes or indices.
 * @kind path-problem
 * @id cpp/integer-overflow-path
 * @severity warning
 * @tags security fuzzing
 */

import cpp
import semmle.code.cpp.dataflow.TaintTracking
import DataFlow::PathGraph

class IntOverflowConfig extends TaintTracking::Configuration {
  IntOverflowConfig() { this = "IntOverflowConfig" }

  override predicate isSource(DataFlow::Node src) {
    // Parameters that receive external/fuzz input
    src.asParameter().getFunction().getName().matches("%parse%") or
    src.asParameter().getFunction().getName().matches("%read%")  or
    src.asParameter().getFunction().getName().matches("%load%")
  }

  override predicate isSink(DataFlow::Node sink) {
    // Arithmetic used as allocation size or array index
    exists(NewArrayExpr nae | sink.asExpr() = nae.getExtent()) or
    exists(ArrayExpr   ae  | sink.asExpr() = ae.getArrayOffset())
  }
}

from IntOverflowConfig cfg, DataFlow::PathNode src, DataFlow::PathNode sink
where cfg.hasFlowPath(src, sink)
select sink.getNode(), src, sink,
  "Integer value from $@ reaches $@ without overflow check.",
  src.getNode(), src.getNode().toString(),
  sink.getNode(), sink.getNode().toString()
