// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import {IllegalState} from "./Errors.sol";

import "./IERC20.sol";
import "./Initializable.sol";
import "./Ownable2StepUpgradeable.sol";

import "./ITokenAdapter.sol";
import "./IStaticAToken.sol";

import "./TokenUtils.sol";
import "./Checker.sol";

/// @title  AaveTokenAdapter
/// @author Savvy DeFi
contract AaveTokenAdapter is
    ITokenAdapter,
    Initializable,
    Ownable2StepUpgradeable
{
    string public constant override version = "1.0.0";

    /// @notice Only SavvyPositionManager can call functions.
    mapping(address => bool) private isAllowlisted;

    /// @notice The address of StaticAToken.
    address public override token;

    address public override baseToken;
    uint8 public tokenDecimals;

    modifier onlyAllowlist() {
        require(isAllowlisted[msg.sender], "Only Allowlist");
        _;
    }

    constructor() {
        _disableInitializers();
    }

    function initialize(address _token) public initializer {
        Checker.checkArgument(
            _token != address(0),
            "token cannot be zero address"
        );

        token = _token;
        baseToken = IStaticAToken(_token).baseToken();
        TokenUtils.safeApprove(baseToken, token, type(uint256).max);
        tokenDecimals = TokenUtils.expectDecimals(token);
        __Ownable2Step_init();
    }

    /// @inheritdoc ITokenAdapter
    function price() external view override returns (uint256) {
        return IStaticAToken(token).staticToDynamicAmount(10 ** tokenDecimals);
    }

    /// @inheritdoc ITokenAdapter
    function addAllowlist(
        address[] memory allowlistAddresses,
        bool status
    ) external override onlyOwner {
        require(allowlistAddresses.length > 0, "invalid length");
        for (uint256 i = 0; i < allowlistAddresses.length; i++) {
            isAllowlisted[allowlistAddresses[i]] = status;
        }
    }

    /// @inheritdoc ITokenAdapter
    function wrap(
        uint256 amount,
        address recipient
    ) external override onlyAllowlist returns (uint256) {
        amount = TokenUtils.safeTransferFrom(
            baseToken,
            msg.sender,
            address(this),
            amount
        );
        Checker.checkArgument(amount > 0, "zero wrap amount");
        // 0 - referral code (deprecated).
        // true - "from underlying", we are depositing the underlying token, not the aToken.
        TokenUtils.safeApprove(baseToken, token, amount);
        return IStaticAToken(token).deposit(recipient, amount, 0, true);
    }

    /// @inheritdoc ITokenAdapter
    function unwrap(
        uint256 amount,
        address recipient
    ) external override onlyAllowlist returns (uint256) {
        amount = TokenUtils.safeTransferFrom(
            token,
            msg.sender,
            address(this),
            amount
        );

        Checker.checkArgument(amount > 0, "zero unwrap amount");

        // true - "to underlying", we are withdrawing the underlying token, not the aToken.
        (uint256 amountBurnt, uint256 amountWithdrawn) = IStaticAToken(token)
            .withdraw(recipient, amount, true);

        Checker.checkState(amountBurnt == amount, "Amount burn mismath");

        return amountWithdrawn;
    }

    uint256[100] private __gap;
}

