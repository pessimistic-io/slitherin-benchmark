// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import {Owned} from "./Owned.sol";
import {SafeTransferLib, ERC20} from "./SafeTransferLib.sol";
import {Token} from "./Token.sol";

/// @notice Two-step redemption process.
contract Redeem is Owned {
    using SafeTransferLib for ERC20;

    /// @notice The token contract.
    Token public immutable token;

    /// @notice Locked tokens (shares) by account.
    mapping(address account => uint256 shares) public lockedShares;

    event Processed(address indexed account, uint256 amount);
    event Lock(address indexed account, uint256 amount);
    event Unlock(address indexed account, uint256 amount);

    constructor(Token _token) Owned(msg.sender) {
        token = _token;
    }

    /// @notice Returns the amount of tokens locked for an account.
    function getLockedAmount(address account) public view returns (uint256) {
        return token.getTokenAmountForShares(lockedShares[account]);
    }

    /// @notice Locks tokens for an account.
    function lock(uint256 amount) external {
        token.transferFrom(msg.sender, address(this), amount);
        lockedShares[msg.sender] += token.getSharesForTokenAmount(amount);
        emit Lock(msg.sender, amount);
    }

    /// @notice Burns locked tokens for an account.
    function burnTokens(address account) external onlyOwner returns (uint256 amount) {
        amount = getLockedAmount(account);
        if (amount > 0) {
            token.burn(amount);
            lockedShares[account] = 0;
            emit Processed(account, amount);
        }
    }

    /// @notice Releases locked tokens back to the account.
    function release(address account) external onlyOwner {
        uint256 shares = lockedShares[account];
        if (shares > 0) {
            token.transferShares(account, shares);
            lockedShares[account] = 0;
            emit Unlock(account, shares);
        }
    }

    /// @notice Transfers tokens out of the contract.
    function transfer(address to, uint256 amount) external onlyOwner {
        ERC20(address(token)).safeTransfer(to, amount);
    }

    /// @notice Burns tokens.
    function burn(uint256 amount) external onlyOwner {
        token.burn(amount);
    }
}

