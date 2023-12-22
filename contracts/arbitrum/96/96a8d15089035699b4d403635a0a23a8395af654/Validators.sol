//contracts/Organizer.sol
//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "./Storage.sol";

/// @title Validators for Organizer Contract
abstract contract Validators is Storage {
  // Is approver?
  function isApprover(address _safeAddress, address _addressToCheck)
    public
    view
    returns (bool)
  {
    require(_addressToCheck != address(0), "CS002");
    require(isOrgOnboarded(_safeAddress), "CS014");
    return orgs[_safeAddress].approvers[_addressToCheck] != address(0);
  }

  // Is Orgs onboarded?
  function isOrgOnboarded(address _addressToCheck) public view returns (bool) {
    require(_addressToCheck != address(0), "CS004");
    return orgs[_addressToCheck].approverCount > 0;
  }
}

