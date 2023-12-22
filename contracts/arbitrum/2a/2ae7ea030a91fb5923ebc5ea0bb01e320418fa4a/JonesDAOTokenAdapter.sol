// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import { IllegalState } from "./Errors.sol";

import "./IERC4626.sol";
import "./Initializable.sol";
import "./Ownable2StepUpgradeable.sol";

import "./Errors.sol";
import "./ITokenAdapter.sol";
import "./IJonesDaoAdapter.sol";
import "./IJonesDaoVaultRouter.sol";
import "./IJGLPViewer.sol";

import { TokenUtils } from "./TokenUtils.sol";
import "./Checker.sol";

/// @title  JonesDAOTokenAdapter (for only USDC)
/// @author Savvy DeFi
contract JonesDAOTokenAdapter is
    ITokenAdapter,
    Initializable,
    Ownable2StepUpgradeable
{
    string public constant override version = "1.0.0";

    /// @notice Only SavvyPositionManager can call functions.
    mapping(address => bool) private isAllowlisted;

    address public override token;
    address public override baseToken;
    address public glpAdapter;
    address public glpVaultRouter;
    address public glpStableVault;
    address public jGLPViewer;

    uint256 public baseTokenDecimals;
    uint8 public tokenDecimals;

    modifier onlyAllowlist() {
        require(isAllowlisted[msg.sender], "Only Allowlist");
        _;
    }

    constructor() {
        _disableInitializers();
    }

    function initialize(address _glpAdapter, address _jGLPViewer) public initializer {
        Checker.checkArgument(_glpAdapter != address(0), "wrong token");

        glpAdapter = _glpAdapter;
        glpVaultRouter = IJonesDaoAdapter(_glpAdapter).vaultRouter();
        glpStableVault = IJonesDaoAdapter(_glpAdapter).stableVault();
        jGLPViewer = _jGLPViewer;
        baseToken = IERC4626(glpStableVault).asset();
        token = IJonesDaoVaultRouter(glpVaultRouter).rewardCompounder(
            baseToken
        );

        baseTokenDecimals = TokenUtils.expectDecimals(baseToken);
        tokenDecimals = TokenUtils.expectDecimals(token);
        __Ownable2Step_init();
    }

    /// @inheritdoc ITokenAdapter
    function price() external view override returns (uint256) {
        (uint256 usdcRedemption,) = IJGLPViewer(jGLPViewer).getUSDCRedemption(1e18, address(this));
        return usdcRedemption;
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
        TokenUtils.safeApprove(baseToken, glpAdapter, amount);
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

        uint256 balanceBefore = TokenUtils.safeBalanceOf(token, address(this));
        TokenUtils.safeApprove(token, glpVaultRouter, amount);
        uint256 amountWithdrawn = _withdraw(amount, recipient);
        uint256 balanceAfter = TokenUtils.safeBalanceOf(token, address(this));
        // If the JonesDAO did not burn all of the shares then revert. This is critical in mathematical operations
        // performed by the system because the system always expects that all of the tokens were unwrapped. In Yearn,
        // this sometimes does not happen in cases where strategies cannot withdraw all of the requested tokens (an
        // example strategy where this can occur is with Compound and AAVE where funds may not be accessible because
        // they were lent out).
        Checker.checkState(
            balanceBefore - balanceAfter == amount,
            "unwrap failed"
        );
        return amountWithdrawn;
    }

    function _deposit(
        uint256 amount,
        address recipient
    ) internal returns (uint256) {
        uint256 balanceBefore = IERC20(token).balanceOf(address(this));
        IJonesDaoAdapter(glpAdapter).depositStable(amount, true);
        uint256 balanceAfter = IERC20(token).balanceOf(address(this));
        uint256 receivedAmount = balanceAfter - balanceBefore;
        require(receivedAmount > 0, "no yieldToken received");
        TokenUtils.safeTransfer(token, recipient, receivedAmount);
        return receivedAmount;
    }

    function _withdraw(
        uint256 amount,
        address recipient
    ) internal returns (uint256) {
        uint256 balanceBefore = IERC20(baseToken).balanceOf(address(this));
        IJonesDaoVaultRouter(glpVaultRouter).stableWithdrawalSignal(
            amount,
            true
        );
        uint256 balanceAfter = IERC20(baseToken).balanceOf(address(this));
        uint256 receivedAmount = balanceAfter - balanceBefore;
        require(receivedAmount > 0, "no baseToken withdrawn");
        TokenUtils.safeTransfer(baseToken, recipient, receivedAmount);
        return receivedAmount;
    }

    receive() external payable {}

    uint256[100] private __gap;
}

