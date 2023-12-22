// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

enum ParameterType {
  Static,
  Dynamic,
  Dynamic32
}

enum Comparison {
  Eq,
  Gte,
  Lte
}

enum Scope {
  None,
  Contract,
  Function
}

enum Operation {
  None,
  Call,
  DelegateCall,
  Both
}

