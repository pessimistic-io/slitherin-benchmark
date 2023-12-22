// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import {IllegalState} from "./Errors.sol";

import "./IERC20.sol";
import "./Initializable.sol";
import "./Ownable2StepUpgradeable.sol";

import "./ITokenAdapter.sol";
import "./IGmdVault.sol";

import "./TokenUtils.sol";
import "./Checker.sol";

/// @title  GmdTokenAdapter
/// @author Savvy DeFi
contract GmdTokenAdapter is
    ITokenAdapter,
    Initializable,
    Ownable2StepUpgradeable
{
    string public constant override version = "1.0.1";

    /// @notice Only SavvyPositionManager can call functions.
    mapping(address => bool) private isAllowlisted;

    /// @notice The address of yieldToken.
    address public override token;

    address public override baseToken;

    address public vaultAddress;

    /// @dev deprecated
    address public WETH;

    /// @notice The GMD pool id for baseToken.
    uint256 public pid;

    uint8 public tokenDecimals;
    uint8 public baseTokenDecimals;

    modifier onlyAllowlist() {
        require(isAllowlisted[msg.sender], "Only Allowlist");
        _;
    }

    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _vaultAddress,
        uint256 _pid
    ) public initializer {
        Checker.checkArgument(
            _vaultAddress != address(0),
            "token cannot be zero address"
        );
        (baseToken, token, , , , , , , , , ) = IGmdVault(_vaultAddress)
            .poolInfo(_pid);
        vaultAddress = _vaultAddress;
        pid = _pid;
        tokenDecimals = TokenUtils.expectDecimals(token);
        baseTokenDecimals = TokenUtils.expectDecimals(baseToken);

        TokenUtils.safeApprove(baseToken, vaultAddress, type(uint256).max);
        TokenUtils.safeApprove(token, vaultAddress, type(uint256).max);

        __Ownable2Step_init();
    }

    /// @inheritdoc ITokenAdapter
    function price() external view override returns (uint256) {
        uint256 gdPrice = IGmdVault(vaultAddress).GDpriceToStakedtoken(pid);
        if (baseTokenDecimals < 18) {
            gdPrice = gdPrice / 10**(18 - baseTokenDecimals);
        }
        return gdPrice;
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
        return _deposit(amount, recipient);
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
        (uint256 amountWithdrawn, uint256 amountBurnt) = _withdraw(
            amount,
            recipient
        );
        Checker.checkState(amountBurnt == amount, "Amount burn mismath");
        return amountWithdrawn;
    }

    function _deposit(
        uint256 amount,
        address recipient
    ) internal returns (uint256) {
        _checkPoolId();
        uint256 beforeBal = TokenUtils.safeBalanceOf(token, address(this));
        IGmdVault(vaultAddress).enter(amount, pid);
        uint256 afterBal = TokenUtils.safeBalanceOf(token, address(this));

        uint256 receivedAmount = afterBal - beforeBal;
        require(receivedAmount > 0, "no yieldToken received");
        TokenUtils.safeTransfer(token, recipient, receivedAmount);
        return receivedAmount;
    }

    function _withdraw(
        uint256 amount,
        address recipient
    ) internal returns (uint256, uint256) {
        _checkPoolId();

        uint256 withdrawnAmount = 0;
        uint256 beforeYieldBal = TokenUtils.safeBalanceOf(token, address(this));
        uint256 beforeBal = TokenUtils.safeBalanceOf(
            baseToken,
            address(this)
        );
        IGmdVault(vaultAddress).leave(amount, pid);
        uint256 afterBal = TokenUtils.safeBalanceOf(
            baseToken,
            address(this)
        );
        withdrawnAmount = afterBal - beforeBal;
        TokenUtils.safeTransfer(baseToken, recipient, withdrawnAmount);
        uint256 afterYieldBal = TokenUtils.safeBalanceOf(token, address(this));
        require(withdrawnAmount > 0, "no withdrawn baseToken");
        return (withdrawnAmount, beforeYieldBal - afterYieldBal);
    }

    function _checkPoolId() internal view {
        (address curBaseToken, address curToken, , , , , , , , , ) = IGmdVault(
            vaultAddress
        ).poolInfo(pid);
        require(baseToken == curBaseToken, "baseToken mismatch");
        require(token == curToken, "yieldToken mismatch");
    }

    receive() external payable {}

    uint256[100] private __gap;
}

