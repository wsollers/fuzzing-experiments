/**
 * @name Out-of-bounds buffer access candidates
 * @description Finds array accesses where the index may exceed the buffer size.
 *              Results feed into fuzzer seed prioritization.
 * @kind problem
 * @id cpp/oob-buffer-access
 * @severity warning
 * @tags security fuzzing
 */

import cpp
import semmle.code.cpp.dataflow.DataFlow

from ArrayExpr ae, Expr idx
where
  idx = ae.getArrayOffset() and
  // Flag accesses where index comes from a function parameter (tainted input)
  exists(Parameter p |
    DataFlow::localFlow(
      DataFlow::parameterNode(p),
      DataFlow::exprNode(idx)
    )
  )
select ae, "Array access at $@ with index derived from parameter $@.",
       ae, ae.getLocation().toString(),
       idx, idx.toString()
