// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {KeeperCompatibleInterface} from "./KeeperCompatibleInterface.sol";
import {IERC20} from "./IERC20.sol";

import {ICommunityIssuance} from "./ICommunityIssuance.sol";
import {Epoch} from "./Epoch.sol";

/**
 * The stability pool keeper gives the stability pool a MAHA reward every 30 days.
 */
contract StabilityPoolKeeper is Epoch, KeeperCompatibleInterface {
    uint256 public mahaRate;
    IERC20 public maha;
    ICommunityIssuance public arthCommunityIssuance;

    constructor(
        ICommunityIssuance _arthCommunityIssuance,
        uint256 _mahaRate,
        IERC20 _maha,
        uint256 _startTime,
        uint256 _startEpoch
    ) Epoch(86400 * 30, _startTime, _startEpoch) {
        arthCommunityIssuance = _arthCommunityIssuance;
        maha = _maha;
        mahaRate = _mahaRate;

        uint256 maxInt = 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;
        maha.approve(address(arthCommunityIssuance), maxInt);
    }

    function updateMahaReward(uint256 reward) external onlyOwner {
        mahaRate = reward;
    }

    function checkUpkeep(bytes calldata _checkData)
        external
        view
        override
        returns (bool, bytes memory)
    {
        return (_callable(), "");
    }

    function performUpkeep(bytes calldata performData)
        external
        override
        checkEpoch
    {
        arthCommunityIssuance.notifyRewardAmount(mahaRate);
    }

    function refund(IERC20 token) external onlyOwner {
        token.transfer(msg.sender, token.balanceOf(address(this)));
    }

    function transferCommunityIssuanceOwnership(address newOperator_)
        external
        onlyOwner
    {
        arthCommunityIssuance.transferOwnership(newOperator_);
    }
}

