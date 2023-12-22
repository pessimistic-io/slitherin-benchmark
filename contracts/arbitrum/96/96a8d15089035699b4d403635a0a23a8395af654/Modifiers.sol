//contracts/Organizer.sol
//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "./Validators.sol";

/// @title Modifiers for Organizer Contract
abstract contract Modifiers is Validators {
  //
  //  Modifiers
  //
  //  Only Onboarded can do this
  modifier onlyOnboarded(address _safeAddress) {
    require(isOrgOnboarded(_safeAddress), "CS014");
    _;
  }

  //  Only Multisig can do this
  modifier onlyMultisig(address _safeAddress) {
    require(msg.sender == _safeAddress, "CS015");
    _;
  }

  //  Only Operators
  modifier onlyApprover(address _safeAddress) {
    require(isApprover(_safeAddress, msg.sender), "CS016");
    _;
  }

  modifier onlyApproverOrMultisig(address _safeAddress) {
    require(
      isApprover(_safeAddress, msg.sender) || msg.sender == _safeAddress,
      "CS017"
    );
    _;
  }
}

