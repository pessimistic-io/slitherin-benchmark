// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import "./Ownable.sol";
import "./SafeERC20.sol";

contract TokenLock is Ownable {
    using SafeERC20 for IERC20;
    IERC20 public immutable token;
    uint256 public immutable unlockTime;

    constructor(IERC20 _token) {
        token = _token;
        unlockTime = block.timestamp + 365 days;
    }

    function withdraw() external onlyOwner {
        require(block.timestamp >= unlockTime, "TokenLock: not unlocked");
        uint256 balance = token.balanceOf(address(this));
        token.safeTransfer(owner(), balance);
    }

    function rescueWrongTokens(IERC20 _token) external onlyOwner {
        require(address(_token) != address(token), "TokenLock: wrong token"); // can not rescue locked tokens
        uint256 balance = _token.balanceOf(address(this));
        _token.safeTransfer(owner(), balance);
    }
}

