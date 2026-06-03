/**
 * @name Uninitialized variable reads
 * @description Detects local variables read before being definitely assigned.
 *              These are high-value fuzzing targets for undefined behaviour.
 * @kind problem
 * @id cpp/uninitialized-read
 * @severity error
 * @tags correctness fuzzing
 */

import cpp
import semmle.code.cpp.dataflow.DataFlow

from LocalVariable v, VariableAccess read
where
  read = v.getAnAccess() and
  read.isRValue() and
  not exists(Expr init | init = v.getInitializer().getExpr()) and
  not exists(AssignExpr assign |
    assign.getLValue().(VariableAccess).getTarget() = v and
    assign.getASuccessor*() = read
  )
select read, "Read of potentially uninitialized variable $@.", v, v.getName()
