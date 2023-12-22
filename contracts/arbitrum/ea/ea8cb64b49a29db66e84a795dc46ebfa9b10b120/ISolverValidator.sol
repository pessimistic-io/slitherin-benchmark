// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity =0.8.17;

interface ISolverValidator {
  function isValidSolver(address solver) external returns (bool valid);
  function setSolverValidity(address solver, bool valid) external;
}

