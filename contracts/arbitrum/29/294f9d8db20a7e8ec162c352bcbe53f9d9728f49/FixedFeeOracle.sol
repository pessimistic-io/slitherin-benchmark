// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.9;

import "./Ownable2Step.sol";

import {IFeeOracle} from "./IFeeOracle.sol";

contract FixedFeeOracle is Ownable2Step, IFeeOracle {
    uint256 public fixedFee;

    event SetFixedFee(uint256 newFixedFee);

    constructor(uint256 fixedFee_) {
        fixedFee = fixedFee_;
    }

    function setFee(uint256 fixedFee_) public onlyOwner {
        fixedFee = fixedFee_;
        emit SetFixedFee(fixedFee_);
    }

    function getFee() public view returns (uint256) {
        return fixedFee;
    }
}

