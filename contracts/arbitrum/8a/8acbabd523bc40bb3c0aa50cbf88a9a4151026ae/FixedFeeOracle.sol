// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.9;

import "./Ownable2Step.sol";

import {IFeeOracle} from "./IFeeOracle.sol";

contract FixedFeeOracle is Ownable2Step, IFeeOracle {
  uint256 public fixedFee;

  struct CustomFee {
    bool exists;
    uint256 fee;
  }

  event SetFixedFee(uint256 newFixedFee);
  event SetCustomFixedFee(
    address indexed account,
    bool state,
    uint256 newFixedFee
  );

  mapping(address => CustomFee) customFees;

  constructor(uint256 fixedFee_) {
    fixedFee = fixedFee_;
  }

  function setFee(uint256 fixedFee_) public onlyOwner {
    fixedFee = fixedFee_;
    emit SetFixedFee(fixedFee_);
  }

  function setCustomFee(
    address account_,
    CustomFee memory customFee_
  ) public onlyOwner {
    customFees[account_] = customFee_;
    emit SetCustomFixedFee(account_, customFee_.exists, customFee_.fee);
  }

  function getFee(address account_, uint256) public view returns (uint256) {
    if (customFees[account_].exists) {
      return customFees[account_].fee;
    }
    return fixedFee;
  }
}

