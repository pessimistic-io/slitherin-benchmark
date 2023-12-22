// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity =0.8.17;


/**
 *    ,,                           ,,                                
 *   *MM                           db                      `7MM      
 *    MM                                                     MM      
 *    MM,dMMb.      `7Mb,od8     `7MM      `7MMpMMMb.        MM  ,MP'
 *    MM    `Mb       MM' "'       MM        MM    MM        MM ;Y   
 *    MM     M8       MM           MM        MM    MM        MM;Mm   
 *    MM.   ,M9       MM           MM        MM    MM        MM `Mb. 
 *    P^YbmdP'      .JMML.       .JMML.    .JMML  JMML.    .JMML. YA.
 *
 *    SolverValidator01.sol :: 0xea8cb64b49a29db66e84a795dc46ebfa9b10b120
 *    etherscan.io verified 2023-12-01
 */ 
import "./Ownable.sol";
import "./ISolverValidator.sol";

contract SolverValidator01 is ISolverValidator, Ownable {

  event SolverValiditySet(address solver, bool valid);

  mapping (address => bool) solverValidity;

  constructor () {
    transferOwnership(0x0AfB7C8cf2b639675a20Fda58Adf3307d40e8E8A);
    solverValidity[0x0AfB7C8cf2b639675a20Fda58Adf3307d40e8E8A] = true;
  }

  function isValidSolver (address solver) external view returns (bool valid) {
    valid = solverValidity[solver];
  }

  function setSolverValidity (address solver, bool valid) external onlyOwner {
    solverValidity[solver] = valid;
    emit SolverValiditySet(solver, valid);
  }
}

