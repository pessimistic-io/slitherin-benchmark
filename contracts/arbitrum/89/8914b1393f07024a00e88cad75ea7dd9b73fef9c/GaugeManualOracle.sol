//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.6;

import {Ownable} from "./Ownable.sol";

contract GaugeManualOracle is Ownable {
    uint256 public rate;

    function getRate(uint256 epochStart, uint256 epochEnd, address gauge) public view returns (uint256 rate) {
        return rate;
    }

    function setRate(uint256 newRate) public onlyOwner {
        rate = newRate;
    }
}
