// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.18;

import {IERC20} from "./IERC20.sol";
import {SafeERC20} from "./SafeERC20.sol";
import {Ownable2Step} from "./Ownable2Step.sol";

/// @title Erc20 reserve
/// @author LevelFinance developer
/// @notice reserve protocol token
contract Erc20Reserve is Ownable2Step {
    using SafeERC20 for IERC20;

    function transfer(IERC20 _token, address _to, uint256 _amount) external onlyOwner {
        if (address(_token) == address(0)) {
            revert InvalidToken();
        }

        if (_to == address(0)) {
            revert InvalidAddress(_to);
        }

        if (_amount == 0) {
            revert InvalidAmount();
        }

        _token.safeTransfer(_to, _amount);
        emit Distributed(_to, _amount);
    }

    event Distributed(address to, uint256 amount);

    error InvalidToken();
    error InvalidAddress(address);
    error InvalidAmount();
}

