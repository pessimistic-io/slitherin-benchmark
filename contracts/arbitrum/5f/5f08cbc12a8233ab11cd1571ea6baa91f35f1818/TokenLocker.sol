// SPDX-License-Identifier: MIT

pragma solidity 0.8.16;

import { ReentrancyGuard }      from "./ReentrancyGuard.sol";
import { Ownable } from "./Ownable.sol";
import { SafeERC20, IERC20 }      from "./SafeERC20.sol";

contract TokenLocker is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    struct Lock {
        uint256 amount;
        uint256 unlockTime;
    }
    Lock public lock;
    IERC20 public immutable lockToken;

    event TokensLocked(IERC20 lockedToken, uint256 amountAddedToLock, uint256 totalAmountLocked, uint256 unlockTimeStamp);
    event TokensUnlocked(IERC20 lockedToken, uint256 amountRemovedFromLock, uint256 remainingAmountLocked);

    constructor(address _lockOwner, address _token) {
        _transferOwnership(_lockOwner);
        lockToken = IERC20(_token);
    }

    function lockTokens(uint256 _amount, uint256 _unlockTime) external onlyOwner nonReentrant {
        if (lock.unlockTime > 0) {
            require(_unlockTime >= lock.unlockTime, "Can not shorten lock");
        } else {
            require(_unlockTime >= block.timestamp + 1 days, "Invalid lock time");
        }
        lock.amount += _amount;
        lock.unlockTime = _unlockTime;
        lockToken.safeTransferFrom(msg.sender, address(this), _amount);
        emit TokensLocked(lockToken, _amount, lock.amount, _unlockTime);
    }

    function withdrawTokens(uint256 _amount) external onlyOwner nonReentrant {
        require(block.timestamp >= lock.unlockTime, "Too soon");
        require(_amount <= lock.amount, "Too many tokens");

        lock.amount -= _amount;
        lockToken.safeTransfer(msg.sender, _amount);
        emit TokensUnlocked(lockToken, _amount, lock.amount);
    } 
}
