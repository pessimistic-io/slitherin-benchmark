// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {Owned} from "./Owned.sol";
import {SafeTransferLib, ERC20} from "./SafeTransferLib.sol";
import {Token} from "./Token.sol";

// Two-step redemption process.
// 1. Minter mints tokens to the vault.
// 2. Owner distributes tokens to users.
contract Redeem is Owned {
    using SafeTransferLib for ERC20;

    Token public immutable token;

    mapping(address user => uint256 shares) public lockedShares;

    event Processed(address indexed user, uint256 amount);
    event Lock(address indexed user, uint256 amount);
    event Unlock(address indexed user, uint256 amount);

    constructor(Token _token) Owned(msg.sender) {
        token = _token;
    }

    function getLockedAmount(address user) public view returns (uint256) {
        return token.getTokenAmountForShares(lockedShares[user]);
    }

    function lock(uint256 amount) external {
        token.transferFrom(msg.sender, address(this), amount);
        lockedShares[msg.sender] += token.getSharesForTokenAmount(amount);
        emit Lock(msg.sender, amount);
    }

    function burnTokens(address user) external onlyOwner returns (uint256 amount) {
        amount = getLockedAmount(user);
        if (amount > 0) {
            token.burn(amount);
            lockedShares[user] = 0;
            emit Processed(user, amount);
        }
    }

    function release(address user) external onlyOwner {
        uint256 shares = lockedShares[user];
        if (shares > 0) {
            token.transferShares(user, shares);
            lockedShares[user] = 0;
            emit Unlock(user, shares);
        }
    }

    function transfer(address to, uint256 amount) external onlyOwner {
        ERC20(address(token)).safeTransfer(to, amount);
    }

    function burn(uint256 amount) external onlyOwner {
        token.burn(amount);
    }
}

