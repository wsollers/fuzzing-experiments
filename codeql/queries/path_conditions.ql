/**
 * @name Path and condition coverage hints
 * @description Identifies branch conditions on externally-tainted values.
 *              The query output is used to seed the fuzzer with inputs that
 *              flip each condition, improving path and condition coverage.
 * @kind problem
 * @id cpp/path-condition-hints
 * @severity recommendation
 * @tags coverage fuzzing
 */

import cpp
import semmle.code.cpp.dataflow.TaintTracking

class PathCondConfig extends TaintTracking::Configuration {
  PathCondConfig() { this = "PathCondConfig" }

  override predicate isSource(DataFlow::Node src) {
    src.asParameter().getFunction().hasName("LLVMFuzzerTestOneInput") or
    // Also track data read from files / sockets
    exists(FunctionCall fc |
      fc.getTarget().getName() in ["fread", "read", "recv", "fgets"] and
      src.asExpr() = fc.getArgument(0)
    )
  }

  override predicate isSink(DataFlow::Node sink) {
    // Branch conditions: if/switch/ternary
    exists(IfStmt is     | sink.asExpr() = is.getCondition()) or
    exists(SwitchStmt ss | sink.asExpr() = ss.getExpr())     or
    exists(Loop l        | sink.asExpr() = l.getCondition())
  }
}

from PathCondConfig cfg, DataFlow::Node src, DataFlow::Node sink, Location loc
where
  cfg.hasFlow(src, sink) and
  loc = sink.asExpr().getLocation()
select sink.asExpr(),
  "Branch at $@:$@ is reachable from fuzz input — add seed to flip this condition.",
  loc, loc.getFile().getBaseName(),
  loc, loc.getStartLine().toString()
