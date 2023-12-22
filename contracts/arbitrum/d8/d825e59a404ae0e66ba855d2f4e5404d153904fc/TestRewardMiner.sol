// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.7.6;
pragma abicoder v2;

import { PerpSafeCast } from "./PerpSafeCast.sol";
import { SafeMathUpgradeable } from "./SafeMathUpgradeable.sol";
import { SignedSafeMathUpgradeable } from "./SignedSafeMathUpgradeable.sol";
import "./RewardMiner.sol";

contract TestRewardMiner is RewardMiner {
    uint256 private _testBlockTimestamp;

    function __TestRewardMiner_init(
        address clearingHouseArg,
        address pnftTokenArg,
        uint256 periodDurationArg,
        uint256[] memory starts,
        uint256[] memory ends,
        uint256[] memory totals,
        uint256 limitClaimPeriodArg
    ) external initializer {
        RewardMiner.initialize(
            clearingHouseArg,
            pnftTokenArg,
            periodDurationArg,
            starts,
            ends,
            totals,
            limitClaimPeriodArg
        );
        _testBlockTimestamp = block.timestamp;
    }

    function setBlockTimestamp(uint256 blockTimestamp) external {
        _testBlockTimestamp = blockTimestamp;
    }

    function getBlockTimestamp() external view returns (uint256) {
        return _testBlockTimestamp;
    }

    function _blockTimestamp() internal view override returns (uint256) {
        return _testBlockTimestamp;
    }
}

