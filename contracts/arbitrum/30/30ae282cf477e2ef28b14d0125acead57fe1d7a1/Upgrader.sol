// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./AccessControlEnumerable.sol";
import {ISuperToken} from "./ISuperfluid.sol";
import {Errors} from "./Errors.sol";
import {IERC20WithDecimals} from "./ERC20_IERC20.sol";

contract Upgrader is AccessControlEnumerable {

    // role identifier for upgrader caller
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_CALLER_ROLE_ID");
    mapping(ISuperToken => bool) public supportedSuperTokens;
    uint8 public constant SUPERTOKEN_DECIMALS = 18;

    constructor(address defaultAdmin, address[] memory upgraders) {
        if (defaultAdmin == address(0)) revert Errors.ZeroAddress();
        _setupRole(DEFAULT_ADMIN_ROLE, defaultAdmin);
        for (uint256 i = 0; i < upgraders.length; i++) {
            if (upgraders[i] == address(0)) revert Errors.ZeroAddress();
            _setupRole(UPGRADER_ROLE, upgraders[i]);
        }
    }

    /**
     * @dev Upgrade ERC20 tokens to Super Tokens on behalf of an account.
     * @param superToken Super Token to upgrade to - must be included in `supportedSuperTokens`
     * @param account Account for which to upgrade
     * @param amount Amount of ERC20 tokens to be upgraded
     * @notice For the call to succeed, this contract needs to have sufficient allowance on the underlying ERC20 tokens.
     * @notice If `msg.sender` equals `account`, it doesn't need to have the upgrader role.
     */
    function upgrade(
        ISuperToken superToken,
        address account,
        uint256 amount
    )
        external
    {
        if (!supportedSuperTokens[superToken]) revert Errors.SuperTokenNotSupported();
        if (msg.sender != account && !hasRole(UPGRADER_ROLE, msg.sender)) {
           revert Errors.OperationNotAllowed();
        }

        // We first transfer ERC20 tokens from the given account to this contract ...
        IERC20WithDecimals erc20Token = IERC20WithDecimals(superToken.getUnderlyingToken());
        uint256 beforeBalance = superToken.balanceOf(address(this));
        if (!erc20Token.transferFrom(account, address(this), amount)) {
            revert Errors.ERC20TransferFromRevert();
        }
        // ... then upgrade them to Super Tokens, scaling the amount in case decimals differ ...
        erc20Token.approve(address(superToken), amount);
        superToken.upgrade(_toSuperTokenAmount(amount, erc20Token.decimals()));
        
        // ... then transfer the newly minted Super Tokens to the account
        if (!superToken.transfer(account, superToken.balanceOf(address(this)) - beforeBalance)) {
            revert Errors.ERC20TransferRevert();
        }
    }

    /**
     * @dev Downgrade Super Tokens to ERC20 tokens on behalf of an account.
     * @param superToken Super Token to downgrade - must be included in `supportedSuperTokens`
     * @param account Account for which to downgrade
     * @param amount Amount of Super Tokens to be downgraded
     * @notice For the call to succeed, this contract needs to have sufficient allowance on the Super Token.
     * @notice If `msg.sender` equals `account`, it doesn't need to have the upgrader role.
     */
    function downgrade(
        ISuperToken superToken,
        address account,
        uint256 amount
    )
        external
    {
        if (!supportedSuperTokens[superToken]) revert Errors.SuperTokenNotSupported();
        if (msg.sender != account && !hasRole(UPGRADER_ROLE, msg.sender)) {
            revert Errors.OperationNotAllowed();
        }

        // We first transfer Super Tokens from the given account to this contract ...
        if (!superToken.transferFrom(account, address(this), amount)) {
            revert Errors.ERC20TransferFromRevert();
        }
        // ... then downgrade them to ERC20 tokens ...
        IERC20WithDecimals erc20Token = IERC20WithDecimals(superToken.getUnderlyingToken());
        uint256 beforeBalance = erc20Token.balanceOf(address(this));
        superToken.downgrade(amount);

        // then transfer the unwrapped ERC20 tokens to the account, scaling the amount in case decimals differ
        if (!erc20Token.transfer(account, erc20Token.balanceOf(address(this)) - beforeBalance)) {
            revert Errors.ERC20TransferRevert();
        }
    }

    // converts erc20 amount based on the given er20 decimals to Super Token amount
    function _toSuperTokenAmount(uint256 amount, uint8 decimals)
        private pure
        returns (uint256 adjustedAmount)
    {
        if (decimals < SUPERTOKEN_DECIMALS) {
            adjustedAmount = amount * (10 ** (SUPERTOKEN_DECIMALS - decimals));
        } else if (decimals > SUPERTOKEN_DECIMALS) {
            adjustedAmount = amount / (10 ** (decimals - SUPERTOKEN_DECIMALS));
        } else {
            adjustedAmount = amount;
        }
    }

    /******************
     * ADMIN INTERFACE
     ******************/

    function addSuperToken(ISuperToken superToken) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (superToken.getUnderlyingToken() == address(0)) {
            revert Errors.SuperTokenNotUnderlying();
        }
        supportedSuperTokens[superToken] = true;
    }

    function removeSuperToken(ISuperToken superToken) external onlyRole(DEFAULT_ADMIN_ROLE) {
        delete supportedSuperTokens[superToken];
    }

    /**
     * @dev Allows admin to add address to upgrader role
     * @param newUpgradeCaller address
     */
    function addUpgrader(address newUpgradeCaller) external {
        if (newUpgradeCaller == address(0)) revert Errors.OperationNotAllowed();
        grantRole(UPGRADER_ROLE, newUpgradeCaller);
    }

    /**
     * @dev Allows admin to remove address from upgrader role
     * @param oldUpgradeCaller address
     */
    function revokeUpgrader(address oldUpgradeCaller) external {
        revokeRole(UPGRADER_ROLE, oldUpgradeCaller);
    }
}

