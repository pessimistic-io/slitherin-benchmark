// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.19;

import {Token} from "./Token.sol";
import {SafeTransferLib, ERC20} from "./SafeTransferLib.sol";

/// @title WrappedToken Contract
/// @notice This contract wraps the rebasing Token contract into a non-rebasing ERC20 token.
/// @dev The wrapped token balance is equivalent to shares in the original token.
contract WrappedToken is ERC20 {
    error Paused();
    error NotWhitelisted();

    Token public immutable token;

    modifier notPaused() {
        if (token.paused()) revert Paused();
        _;
    }

    modifier onlyWhitelisted(address account) {
        if (!token.isWhitelisted(account)) revert NotWhitelisted();
        _;
    }

    constructor(Token _token) ERC20("", "", _token.decimals()) {
        token = _token;
        updateName();
    }

    /// @notice Updates the wrapped token name and symbol to match the original token.
    function updateName() public {
        name = string.concat("Wrapped ", token.name());
        symbol = string.concat("w", token.symbol());
    }

    /// @notice Wraps a specified amount of the original token into wrapped tokens.
    /// @param amount The amount of the original token to wrap.
    /// @return shares The amount of wrapped tokens minted.
    function wrap(uint256 amount) external returns (uint256 shares) {
        token.transferFrom(msg.sender, address(this), amount);
        shares = token.getSharesForTokenAmount(amount);
        _mint(msg.sender, shares);
    }

    /// @notice Unwraps a specified amount of the wrapped token into the original token.
    /// @param amount The amount of "shares" to unwrap.
    /// @return tokenAmount The amount of the original token received.
    function unwrap(uint256 amount) external returns (uint256 tokenAmount) {
        _burn(msg.sender, amount);
        return token.transferShares(msg.sender, amount);
    }

    /// @dev Overrides transfer function to check if the recipient is whitelisted and the token is not paused.
    function transfer(address to, uint256 amount) public override onlyWhitelisted(to) notPaused returns (bool) {
        return super.transfer(to, amount);
    }

    /// @dev Overrides transferFrom function to check if the recipient is whitelisted and the token is not paused.
    function transferFrom(address from, address to, uint256 amount)
        public
        override
        onlyWhitelisted(to)
        notPaused
        returns (bool)
    {
        return super.transferFrom(from, to, amount);
    }
}

