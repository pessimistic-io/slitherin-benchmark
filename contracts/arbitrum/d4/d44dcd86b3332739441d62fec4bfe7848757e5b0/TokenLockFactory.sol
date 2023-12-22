// SPDX-License-Identifier: MIT

pragma solidity 0.8.16;

import { ReentrancyGuard } from "./ReentrancyGuard.sol";
import { TokenLocker } from "./TokenLocker.sol";

contract TokenLockFactory is ReentrancyGuard {

    address[] public lockers;

    event LockerCreated(address lockedToken, address lockOwner);

    function createTokenLocker(address _token) external nonReentrant returns (address locker) {
        TokenLocker _locker = new TokenLocker(msg.sender, _token);
        locker = address(_locker);
        lockers.push(locker);
        emit LockerCreated(_token, msg.sender);
    }

}
