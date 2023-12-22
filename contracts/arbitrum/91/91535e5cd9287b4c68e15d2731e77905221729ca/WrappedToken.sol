// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.20;

import {Token} from "./Token.sol";
import {ERC20} from "./token_ERC20.sol";
import {SafeTransferLib} from "./SafeTransferLib.sol";
import {OwnableUpgradeable} from "./OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "./UUPSUpgradeable.sol";

/// @title WrappedToken Contract
/// @notice This contract wraps the rebasing Token contract into a non-rebasing ERC20 token.
/// @dev The wrapped token balance is equivalent to shares in the original token.
contract WrappedToken is UUPSUpgradeable, ERC20, OwnableUpgradeable {
    error Paused();
    error NotAllowed();
    error NotBlocked();

    Token public token;

    modifier notPaused() {
        if (token.paused()) revert Paused();
        _;
    }

    modifier onlyAllowed(address account) {
        if (!token.canTransact(account)) revert NotAllowed();
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes the wrapped token contract.
    function initialize(Token _token, address _owner) initializer public {
        token = _token;
        __Ownable_init(_owner);
        __ERC20_init_(_token.decimals());
        updateName();
    }

    /// @notice Implementation of the UUPS proxy authorization.
    function _authorizeUpgrade(address) internal override onlyOwner {}

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

    /// @notice Transfers tokens from a blacklisted account.
    /// @param from The address to take tokens from.
    /// @param amount The amount of tokens to move.
    function moveTokens(address from, address to, uint256 amount) external onlyOwner {
        if (!token.allowlist().blocked(from)) revert NotBlocked();
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        emit Transfer(from, to, amount);
    }

    /// @dev Overrides transfer function to check if the recipient is allowed and the token is not paused.
    function transfer(address to, uint256 amount) public override onlyAllowed(msg.sender) onlyAllowed(to) notPaused returns (bool) {
        return super.transfer(to, amount);
    }

    /// @dev Overrides transferFrom function to check if the recipient is allowed and the token is not paused.
    function transferFrom(address from, address to, uint256 amount)
        public
        override
        onlyAllowed(from)
        onlyAllowed(to)
        notPaused
        returns (bool)
    {
        return super.transferFrom(from, to, amount);
    }
}

