// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./SafeMath.sol";
import "./Ownable.sol";

contract TimeSkippable is Ownable {
    using SafeMath for uint256;
    uint256 public skippedTime;
    uint256 public overridedTime;

    function resetSkipTime() public onlyOwner {
        skippedTime = 0;
        overridedTime = 0;
    }

    function skip(uint256 numberOfday) public onlyOwner {
        skippedTime = skippedTime.add(numberOfday.mul(86400));
    }

    function skipMilis(uint256 milis) public onlyOwner {
        skippedTime = skippedTime.add(milis);
    }

    function setOveridedTime(uint256 _overridedTime) public onlyOwner {
        overridedTime = _overridedTime;
    }

    function getNow() public view returns (uint256) {
        if (overridedTime > 0) return overridedTime;
        return skippedTime.add(block.timestamp);
    }
}

