// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./SafeMath.sol";
import "./CloudTrait.sol";

contract RewardManager {
    using SafeMath for uint256;

    function getRewardPerToken(
        uint256 _s,
        uint256 _e,
        uint256 _yield,
        uint256 _price
    ) public pure returns (uint256) {
        uint256 secondSpent = _e.sub(
            _s
        );
        uint256 rewardPerSeconds = (_yield).mul(_price).div(100000*365*86400);
        uint256 rewards = rewardPerSeconds.mul(
            secondSpent
        );
        return rewards;
    }

    function getClaimTax(CloudTrait.Level _level) public pure returns(uint256) {
        require(
            _level == (CloudTrait.Level.Beginner) ||
            _level == (CloudTrait.Level.Intermediate) ||
            _level == (CloudTrait.Level.Advanced),
            "ERR: Level does not exist"
        );
        if (_level == (CloudTrait.Level.Intermediate)) {
            return 75;
        }
        if (_level == (CloudTrait.Level.Advanced)) {
            return 50;
        }
        return 100;
    }
}
