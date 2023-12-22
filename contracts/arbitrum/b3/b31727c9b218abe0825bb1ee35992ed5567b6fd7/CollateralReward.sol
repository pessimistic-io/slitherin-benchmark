// SPDX-License-Identifier: MIT

pragma solidity =0.8.4;

import { Initializable } from "./Initializable.sol";
import { IERC20Upgradeable } from "./IERC20Upgradeable.sol";
import { SafeERC20Upgradeable } from "./SafeERC20Upgradeable.sol";
import { ReentrancyGuardUpgradeable } from "./ReentrancyGuardUpgradeable.sol";

import "./BaseReward.sol";

contract CollateralReward is BaseReward {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    function withdrawFor(address _recipient, uint256 _amountOut) public override nonReentrant onlyOperator returns (uint256) {
        _updateRewards(_recipient);

        User storage user = users[_recipient];

        require(_amountOut <= user.totalUnderlying, "CollateralReward: Insufficient amounts");

        user.totalUnderlying = user.totalUnderlying - _amountOut;

        totalSupply = totalSupply - _amountOut;

        IERC20Upgradeable(stakingToken).safeTransfer(operator, _amountOut);

        emit Withdraw(_recipient, _amountOut, totalSupply, user.totalUnderlying);

        return _amountOut;
    }

    function withdraw(uint256) public override nonReentrant returns (uint256) {
        revert("CollateralReward: Not allowed");
    }
}

