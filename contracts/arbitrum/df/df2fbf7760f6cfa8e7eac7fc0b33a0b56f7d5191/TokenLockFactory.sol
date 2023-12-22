// SPDX-License-Identifier: MIT

pragma solidity 0.8.16;

import { ReentrancyGuard } from "./ReentrancyGuard.sol";
import { SafeERC20, IERC20 }      from "./SafeERC20.sol";
import { TokenLocker } from "./TokenLocker.sol";

contract TokenLockFactory is ReentrancyGuard {
    using SafeERC20 for IERC20;

    address[] public lockers;

    event LockerCreated(address lockedToken, address lockOwner);

    function createTokenLocker(address _token, uint256 _lockAmount, uint256 _unlockTime) external nonReentrant returns (address locker) {
        TokenLocker _locker = new TokenLocker(msg.sender, _token, _lockAmount, _unlockTime);
        locker = address(_locker);
        lockers.push(locker);

        IERC20(_token).safeTransferFrom(msg.sender, locker, _lockAmount);
        emit LockerCreated(_token, msg.sender);
    }

}
