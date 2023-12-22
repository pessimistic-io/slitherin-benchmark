// SPDX-License-Identifier: MIT

pragma solidity 0.8.18;

import {SafeERC20} from "./SafeERC20.sol";
import {IERC20} from "./IERC20.sol";
import {ILevelOmniStaking} from "./ILevelOmniStaking.sol";

contract LevelDaoClaimHelper {
    using SafeERC20 for IERC20;

    ILevelOmniStaking public lvlStaking;
    ILevelOmniStaking public lvlUsdtStaking;

    constructor(address _lvlStaking, address _lvlUsdtStaking) {
        if (_lvlStaking == address(0)) revert ZeroAddress();
        if (_lvlUsdtStaking == address(0)) revert ZeroAddress();
        lvlStaking = ILevelOmniStaking(_lvlStaking);
        lvlUsdtStaking = ILevelOmniStaking(_lvlUsdtStaking);
    }

    // =============== USER FUNCTIONS ===============
    function claimRewards(uint256[] calldata _epochs, address _to) external {
        uint256 _length = _epochs.length;
        for (uint256 i = 0; i < _length;) {
            uint256 _epoch = _epochs[i];
            lvlStaking.claimRewardsOnBehalf(msg.sender, _epoch, _to);
            lvlUsdtStaking.claimRewardsOnBehalf(msg.sender, _epoch, _to);

            unchecked {
                ++i;
            }
        }
    }

    // =============== ERRORS ===============
    error ZeroAddress();
}

