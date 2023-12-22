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
 *    SolverValidator01.sol :: 0x598f419ba9e6b37d802bb51d247e373aa3b6b99f
 *    etherscan.io verified 2023-12-01
 */ 
import "./Ownable.sol";
import "./ISolverValidator.sol";

contract SolverValidator01 is ISolverValidator, Ownable {

  mapping (address => bool) solverValidity;

  constructor () {
    transferOwnership(0x0AfB7C8cf2b639675a20Fda58Adf3307d40e8E8A);
  }

  function isValidSolver (address solver) external returns (bool valid) {
    valid = solverValidity[solver];
  }

  function setSolverValidity (address solver, bool valid) external onlyOwner {
    solverValidity[solver] = valid;
  }
}

