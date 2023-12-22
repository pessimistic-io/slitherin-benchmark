// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.7.6;
pragma abicoder v2;

import { AddressUpgradeable } from "./AddressUpgradeable.sol";
import { ReentrancyGuardUpgradeable } from "./ReentrancyGuardUpgradeable.sol";
import { SafeMathUpgradeable } from "./SafeMathUpgradeable.sol";
import { SignedSafeMathUpgradeable } from "./SignedSafeMathUpgradeable.sol";
import { MathUpgradeable } from "./MathUpgradeable.sol";
import { SafeERC20Upgradeable, IERC20Upgradeable } from "./SafeERC20Upgradeable.sol";
import { FullMath } from "./FullMath.sol";
import { TransferHelper } from "./TransferHelper.sol";
import { PerpSafeCast } from "./PerpSafeCast.sol";
import { PerpMath } from "./PerpMath.sol";
import { IERC20Metadata } from "./IERC20Metadata.sol";
import { IInsuranceFund } from "./IInsuranceFund.sol";
import { IVPool } from "./IVPool.sol";
import { IAccountBalance } from "./IAccountBalance.sol";
import { IClearingHouseConfig } from "./IClearingHouseConfig.sol";
import { IClearingHouse } from "./IClearingHouse.sol";
import { BaseRelayRecipient } from "./BaseRelayRecipient.sol";
import { OwnerPausable } from "./OwnerPausable.sol";
import { VaultStorageV2 } from "./VaultStorage.sol";
import { IVault } from "./IVault.sol";
import { IWETH9 } from "./IWETH9.sol";

// never inherit any new stateful contract. never change the orders of parent stateful contracts
contract Vault is IVault, ReentrancyGuardUpgradeable, OwnerPausable, BaseRelayRecipient, VaultStorageV2 {
    using SafeMathUpgradeable for uint256;
    using PerpSafeCast for uint256;
    using PerpSafeCast for int256;
    using SignedSafeMathUpgradeable for int256;
    using PerpMath for int256;
    using PerpMath for uint256;
    using PerpMath for uint24;
    using FullMath for uint256;
    using AddressUpgradeable for address;

    uint24 private constant _ONE_HUNDRED_PERCENT_RATIO = 1e6;

    //
    // MODIFIER
    //

    modifier onlySettlementOrCollateralToken(address token) {
        // V_OSCT: only settlement or collateral token
        require(token == _settlementToken || _isCollateral(token), "V_OSCT");
        _;
    }

    function _requireNotMaker(address maker) internal view {
        // only Maker
        require(maker != _maker, "V_NM");
    }

    function _requireOnlyMaker(address maker) internal view {
        // only Maker
        require(maker == _maker, "V_OM");
    }

    //
    // EXTERNAL NON-VIEW
    //

    /// @dev only used for unwrapping weth in withdrawETH
    receive() external payable {
        // V_SNW: sender is not WETH9
        require(_msgSender() == _WETH9, "V_SNW");
    }

    function initialize(
        address insuranceFundArg,
        address clearingHouseConfigArg,
        address accountBalanceArg,
        address exchangeArg,
        address makerArg
    ) external initializer {
        address settlementTokenArg = IInsuranceFund(insuranceFundArg).getToken();
        uint8 decimalsArg = IERC20Metadata(settlementTokenArg).decimals();

        // invalid settlementToken decimals
        require(decimalsArg <= 18, "V_ISTD");
        // ClearingHouseConfig address is not contract
        require(clearingHouseConfigArg.isContract(), "V_CHCNC");
        // accountBalance address is not contract
        require(accountBalanceArg.isContract(), "V_ABNC");
        // exchange address is not contract
        require(exchangeArg.isContract(), "V_ENC");

        __ReentrancyGuard_init();
        __OwnerPausable_init();

        // update states
        _decimals = decimalsArg;
        _settlementToken = settlementTokenArg;
        _insuranceFund = insuranceFundArg;
        _clearingHouseConfig = clearingHouseConfigArg;
        _accountBalance = accountBalanceArg;
        _vPool = exchangeArg;
        _maker = makerArg;
    }

    function setTrustedForwarder(address trustedForwarderArg) external onlyOwner {
        // V_TFNC: TrustedForwarder address is not contract
        require(trustedForwarderArg.isContract(), "V_TFNC");

        _setTrustedForwarder(trustedForwarderArg);
        emit TrustedForwarderChanged(trustedForwarderArg);
    }

    function setClearingHouse(address clearingHouseArg) external onlyOwner {
        // V_CHNC: ClearingHouse is not contract
        require(clearingHouseArg.isContract(), "V_CHNC");

        _clearingHouse = clearingHouseArg;
        emit ClearingHouseChanged(clearingHouseArg);
    }

    function setMaker(address makerArg) external onlyOwner {
        // V_CHNC: Maker is not contract
        // require(makerArg.isContract(), "V_CHNC");

        _maker = makerArg;
        emit MakerChanged(makerArg);
    }

    function setWETH9(address WETH9Arg) external onlyOwner {
        // V_WNC: WETH9 is not contract
        require(WETH9Arg.isContract(), "V_WNC");

        _WETH9 = WETH9Arg;
        emit WETH9Changed(WETH9Arg);
    }

    /// @inheritdoc IVault
    function deposit(
        address token,
        uint256 amount
    ) external override whenNotPaused nonReentrant onlySettlementOrCollateralToken(token) {
        // input requirement checks:
        //   token: here
        //   amount: _deposit

        address from = _msgSender();
        _deposit(from, from, token, amount);
    }

    /// @inheritdoc IVault
    function depositFor(
        address to,
        address token,
        uint256 amount
    ) external override whenNotPaused nonReentrant onlySettlementOrCollateralToken(token) {
        // input requirement checks:
        //   token: here
        //   amount: _deposit

        // V_DFZA: Deposit for zero address
        require(to != address(0), "V_DFZA");

        address from = _msgSender();
        _deposit(from, to, token, amount);
    }

    /// @inheritdoc IVault
    function depositEther() external payable override whenNotPaused nonReentrant {
        address to = _msgSender();
        _depositEther(to);
    }

    /// @inheritdoc IVault
    function depositEtherFor(address to) external payable override whenNotPaused nonReentrant {
        // input requirement checks:
        //   to: here

        // V_DFZA: Deposit for zero address
        require(to != address(0), "V_DFZA");
        _depositEther(to);
    }

    /// @inheritdoc IVault
    // the full process of withdrawal:
    // 1. settle funding payment to owedRealizedPnl
    // 2. collect fee to owedRealizedPnl
    // 3. call Vault.withdraw(token, amount)
    // 4. settle pnl to trader balance in Vault
    // 5. transfer the amount to trader
    function withdraw(
        address token,
        uint256 amount
    ) external override whenNotPaused nonReentrant onlySettlementOrCollateralToken(token) {
        // input requirement checks:
        //   token: here
        //   amount: in _settleAndDecreaseBalance()

        address to = _msgSender();
        _withdraw(to, token, amount);
    }

    /// @inheritdoc IVault
    function withdrawEther(uint256 amount) external override whenNotPaused nonReentrant {
        // input requirement checks:
        //   amount: in _settleAndDecreaseBalance()

        _requireWETH9IsCollateral();

        address to = _msgSender();

        _withdrawEther(to, amount);
    }

    /// @inheritdoc IVault
    function withdrawAll(
        address token
    ) external override whenNotPaused nonReentrant onlySettlementOrCollateralToken(token) returns (uint256 amount) {
        // input requirement checks:
        //   token: here

        address to = _msgSender();
        amount = getFreeCollateralByToken(to, token);

        _withdraw(to, token, amount);
        return amount;
    }

    /// @inheritdoc IVault
    function withdrawAllEther() external override whenNotPaused nonReentrant returns (uint256 amount) {
        _requireWETH9IsCollateral();

        address to = _msgSender();
        amount = getFreeCollateralByToken(to, _WETH9);

        _withdrawEther(to, amount);
        return amount;
    }

    //
    // EXTERNAL VIEW
    //

    /// @inheritdoc IVault
    function getSettlementToken() external view override returns (address) {
        return _settlementToken;
    }

    /// @inheritdoc IVault
    function decimals() external view override returns (uint8) {
        return _decimals;
    }

    /// @inheritdoc IVault
    function getTotalDebt() external view override returns (uint256) {
        return _totalDebt;
    }

    /// @inheritdoc IVault
    function getClearingHouseConfig() external view override returns (address) {
        return _clearingHouseConfig;
    }

    /// @inheritdoc IVault
    function getAccountBalance() external view override returns (address) {
        return _accountBalance;
    }

    /// @inheritdoc IVault
    function getInsuranceFund() external view override returns (address) {
        return _insuranceFund;
    }

    /// @inheritdoc IVault
    function getVPool() external view override returns (address) {
        return _vPool;
    }

    /// @inheritdoc IVault
    function getClearingHouse() external view override returns (address) {
        return _clearingHouse;
    }

    /// @inheritdoc IVault
    function getWETH9() external view override returns (address) {
        return _WETH9;
    }

    /// @inheritdoc IVault
    function getFreeCollateral(address trader) external view override returns (uint256) {
        return _getFreeCollateral(trader).formatSettlementToken(_decimals);
    }

    /// @inheritdoc IVault
    function getFreeCollateralByRatio(address trader, uint24 ratio) external view override returns (int256) {
        return _getFreeCollateralByRatio(trader, ratio).formatSettlementToken(_decimals);
    }

    /// @inheritdoc IVault
    function getSettlementTokenValue(address trader) external view override returns (int256) {
        return _getSettlementTokenValue(trader).formatSettlementToken(_decimals);
    }

    /// @inheritdoc IVault
    function getAccountValue(address trader) external view override returns (int256) {
        (int256 accountValueX10_18, ) = _getAccountValueAndTotalCollateralValue(trader);
        return accountValueX10_18.formatSettlementToken(_decimals);
    }

    /// @inheritdoc IVault
    function getCollateralTokens(address trader) external view override returns (address[] memory) {
        return _collateralTokensMap[trader];
    }

    //
    // PUBLIC VIEW
    //

    /// @inheritdoc IVault
    function getBalance(address trader) public view override returns (int256) {
        return _balance[trader][_settlementToken];
    }

    /// @inheritdoc IVault
    function getBalanceByToken(address trader, address token) public view override returns (int256) {
        return _balance[trader][token];
    }

    /// @inheritdoc IVault
    /// @dev getFreeCollateralByToken(token) = (getSettlementTokenValue() >= 0)
    ///   ? min(getFreeCollateral() / indexPrice[token], getBalanceByToken(token))
    ///   : 0
    /// @dev if token is settlementToken, then indexPrice[token] = 1
    function getFreeCollateralByToken(address trader, address token) public view override returns (uint256) {
        // do not check settlementTokenValue == 0 because user's settlement token balance may be zero
        if (_getSettlementTokenValue(trader) < 0) {
            return 0;
        }

        uint256 freeCollateralX10_18 = _getFreeCollateral(trader);
        if (freeCollateralX10_18 == 0) {
            return 0;
        }

        if (token == _settlementToken) {
            (int256 settlementTokenBalanceX10_18, ) = _getSettlementTokenBalanceAndUnrealizedPnl(trader);
            return
                settlementTokenBalanceX10_18 <= 0
                    ? 0
                    : MathUpgradeable
                        .min(freeCollateralX10_18, settlementTokenBalanceX10_18.toUint256())
                        .formatSettlementToken(_decimals);
        }

        revert("V_NS");
    }

    /// @inheritdoc IVault
    /// @dev will only settle the bad debt when trader didn't have position and non-settlement collateral
    function settleBadDebt(address trader) public override {
        // V_CSI: can't settle insuranceFund
        require(trader != _insuranceFund, "V_CSI");

        // trader has position or trader has non-settlement collateral
        if (
            IAccountBalance(_accountBalance).getBaseTokens(trader).length != 0 ||
            _collateralTokensMap[trader].length != 0
        ) {
            return;
        }

        // assume trader has no position and no non-settlement collateral
        // so accountValue = settlement token balance
        (int256 accountValueX10_18, ) = _getSettlementTokenBalanceAndUnrealizedPnl(trader);
        int256 accountValueX10_S = accountValueX10_18.formatSettlementToken(_decimals);

        if (accountValueX10_S >= 0) {
            return;
        }

        // settle bad debt for trader
        int256 badDebt = accountValueX10_S.neg256();
        address settlementToken = _settlementToken; // SLOAD gas saving
        _modifyBalance(_insuranceFund, settlementToken, accountValueX10_S);
        _modifyBalance(trader, settlementToken, badDebt);

        uint256 absBadDebt = badDebt.toUint256();
        emit BadDebtSettled(trader, absBadDebt);
    }

    //
    // INTERNAL NON-VIEW
    //

    /// @param token the collateral token needs to be transferred into vault
    /// @param from the address of account who owns the collateral token
    /// @param amount the amount of collateral token needs to be transferred
    function _transferTokenIn(address token, address from, uint256 amount) internal {
        // check for deflationary tokens by assuring balances before and after transferring to be the same
        uint256 balanceBefore = IERC20Metadata(token).balanceOf(address(this));
        SafeERC20Upgradeable.safeTransferFrom(IERC20Upgradeable(token), from, address(this), amount);
        // V_IBA: inconsistent balance amount, to prevent from deflationary tokens
        require((IERC20Metadata(token).balanceOf(address(this)).sub(balanceBefore)) == amount, "V_IBA");
    }

    /// @param from deposit token from this address
    /// @param to deposit token to this address
    /// @param token the collateral token wish to deposit
    /// @param amount the amount of token to deposit
    function _deposit(address from, address to, address token, uint256 amount) internal {
        _requireNotMaker(from);
        _requireNotMaker(to);
        // V_ZA: Zero amount
        require(amount > 0, "V_ZA");
        _transferTokenIn(token, from, amount);
        _checkDepositCapAndRegister(token, to, amount);
    }

    /// @param to deposit ETH to this address
    function _depositEther(address to) internal {
        _requireNotMaker(to);
        uint256 amount = msg.value;
        // V_ZA: Zero amount
        require(amount > 0, "V_ZA");
        _requireWETH9IsCollateral();

        // SLOAD for gas saving
        address WETH9 = _WETH9;
        // wrap ETH into WETH
        IWETH9(WETH9).deposit{ value: amount }();
        _checkDepositCapAndRegister(WETH9, to, amount);
    }

    /// @param token the collateral token needs to be transferred out of vault
    /// @param to the address of account that the collateral token deposit to
    /// @param amount the amount of collateral token to be deposited
    function _checkDepositCapAndRegister(address token, address to, uint256 amount) internal {
        if (token == _settlementToken) {
            uint256 settlementTokenBalanceCap = IClearingHouseConfig(_clearingHouseConfig)
                .getSettlementTokenBalanceCap();
            // V_GTSTBC: greater than settlement token balance cap
            require(IERC20Metadata(token).balanceOf(address(this)) <= settlementTokenBalanceCap, "V_GTSTBC");
        } else {
            // V_NS: sot support
            revert("V_NS");
        }
        _modifyBalance(to, token, amount.toInt256());
        emit Deposited(token, to, amount);
    }

    function _settleAndDecreaseBalance(address to, address token, uint256 amount) internal {
        // settle all funding payments owedRealizedPnl
        // pending fee can be withdraw but won't be settled
        IClearingHouse(_clearingHouse).settleAllFunding(to);

        // incl. owedRealizedPnl
        uint256 freeCollateral = getFreeCollateralByToken(to, token);
        // V_NEFC: not enough freeCollateral
        require(freeCollateral >= amount, "V_NEFC");

        int256 deltaBalance = amount.toInt256().neg256();
        if (token == _settlementToken) {
            // settle both the withdrawn amount and owedRealizedPnl to collateral
            int256 owedRealizedPnlX10_18 = IAccountBalance(_accountBalance).settleOwedRealizedPnl(to);
            deltaBalance = deltaBalance.add(owedRealizedPnlX10_18.formatSettlementToken(_decimals));
        }

        _modifyBalance(to, token, deltaBalance);
    }

    function _withdraw(address to, address token, uint256 amount) internal {
        _requireNotMaker(to);

        _settleAndDecreaseBalance(to, token, amount);
        SafeERC20Upgradeable.safeTransfer(IERC20Upgradeable(token), to, amount);
        emit Withdrawn(token, to, amount);
    }

    function _withdrawEther(address to, uint256 amount) internal {
        _requireNotMaker(to);

        // SLOAD for gas saving
        address WETH9 = _WETH9;

        _settleAndDecreaseBalance(to, WETH9, amount);

        IWETH9(WETH9).withdraw(amount);
        TransferHelper.safeTransferETH(to, amount);
        emit Withdrawn(WETH9, to, amount);
    }

    /// @param amount can be 0; do not require this
    function _modifyBalance(address trader, address token, int256 amount) internal {
        if (amount == 0) {
            return;
        }

        int256 oldBalance = _balance[trader][token];
        int256 newBalance = oldBalance.add(amount);
        _balance[trader][token] = newBalance;

        if (token == _settlementToken) {
            return;
        }
        // V_NS: not yet supported
        revert("V_NS");
    }

    //
    // INTERNAL VIEW
    //

    function _getFreeCollateral(address trader) internal view returns (uint256 freeCollateralX10_18) {
        return
            PerpMath
                .max(_getFreeCollateralByRatio(trader, IClearingHouseConfig(_clearingHouseConfig).getImRatio()), 0)
                .toUint256();
    }

    function _getFreeCollateralByRatio(
        address trader,
        uint24 ratio
    ) internal view returns (int256 freeCollateralX10_18) {
        // conservative config: freeCollateral = min(totalCollateralValue, accountValue) - openOrderMarginReq
        (int256 accountValueX10_18, int256 totalCollateralValueX10_18) = _getAccountValueAndTotalCollateralValue(
            trader
        );
        uint256 totalMarginRequirementX10_18 = _getTotalMarginRequirement(trader, ratio);

        return
            PerpMath.min(totalCollateralValueX10_18, accountValueX10_18).sub(totalMarginRequirementX10_18.toInt256());

        // moderate config: freeCollateral = min(totalCollateralValue, accountValue - openOrderMarginReq)
        // return
        //     PerpMath.min(
        //         totalCollateralValueX10_18,
        //         accountValueX10_S.sub(totalMarginRequirementX10_18.toInt256())
        //     );

        // aggressive config: freeCollateral = accountValue - openOrderMarginReq
        // note that the aggressive model depends entirely on unrealizedPnl, which depends on the index price
        //      we should implement some sort of safety check before using this model; otherwise,
        //      a trader could drain the entire vault if the index price deviates significantly.
        // return accountValueX10_18.sub(totalMarginRequirementX10_18.toInt256());
    }

    function _getTotalCollateralValueAndUnrealizedPnl(
        address trader
    ) internal view returns (int256 totalCollateralValueX10_18, int256 unrealizedPnlX10_18) {
        int256 settlementTokenBalanceX10_18;
        (settlementTokenBalanceX10_18, unrealizedPnlX10_18) = _getSettlementTokenBalanceAndUnrealizedPnl(trader);
        return (settlementTokenBalanceX10_18, unrealizedPnlX10_18);
    }

    /// @notice Get the specified trader's settlement token balance, including pending fee, funding payment,
    ///         owed realized PnL, but without unrealized PnL)
    /// @dev Note the difference between the return argument`settlementTokenBalanceX10_18` and
    ///      the return value of `getSettlementTokenValue()`.
    ///      The first one is settlement token balance with pending fee, funding payment, owed realized PnL;
    ///      The second one is the first one plus unrealized PnL.
    /// @return settlementTokenBalanceX10_18 Settlement amount in 18 decimals
    /// @return unrealizedPnlX10_18 Unrealized PnL in 18 decimals
    function _getSettlementTokenBalanceAndUnrealizedPnl(
        address trader
    ) internal view returns (int256 settlementTokenBalanceX10_18, int256 unrealizedPnlX10_18) {
        int256 fundingPaymentX10_18 = IVPool(_vPool).getAllPendingFundingPayment(trader);

        int256 owedRealizedPnlX10_18;
        uint256 pendingFeeX10_18;
        (owedRealizedPnlX10_18, unrealizedPnlX10_18, pendingFeeX10_18) = IAccountBalance(_accountBalance)
            .getPnlAndPendingFee(trader);

        settlementTokenBalanceX10_18 = getBalance(trader).parseSettlementToken(_decimals).add(
            pendingFeeX10_18.toInt256().sub(fundingPaymentX10_18).add(owedRealizedPnlX10_18)
        );

        return (settlementTokenBalanceX10_18, unrealizedPnlX10_18);
    }

    /// @return settlementTokenValueX10_18 settlementTokenBalance + totalUnrealizedPnl, in 18 decimals
    function _getSettlementTokenValue(address trader) internal view returns (int256 settlementTokenValueX10_18) {
        (int256 settlementBalanceX10_18, int256 unrealizedPnlX10_18) = _getSettlementTokenBalanceAndUnrealizedPnl(
            trader
        );
        return settlementBalanceX10_18.add(unrealizedPnlX10_18);
    }

    function _getAccountValueAndTotalCollateralValue(
        address trader
    ) internal view returns (int256 accountValueX10_18, int256 totalCollateralValueX10_18) {
        int256 unrealizedPnlX10_18;

        (totalCollateralValueX10_18, unrealizedPnlX10_18) = _getTotalCollateralValueAndUnrealizedPnl(trader);

        // accountValue = totalCollateralValue + totalUnrealizedPnl, in 18 decimals
        accountValueX10_18 = totalCollateralValueX10_18.add(unrealizedPnlX10_18);

        return (accountValueX10_18, totalCollateralValueX10_18);
    }

    /// @return totalMarginRequirementX10_18 total margin requirement in 18 decimals
    function _getTotalMarginRequirement(
        address trader,
        uint24 ratio
    ) internal view returns (uint256 totalMarginRequirementX10_18) {
        // uint256 totalDebtValueX10_18 = IAccountBalance(_accountBalance).getTotalDebtValue(trader);
        uint256 totalDebtValueX10_18 = IAccountBalance(_accountBalance).getTotalAbsPositionValue(trader);
        return totalDebtValueX10_18.mulRatio(ratio);
    }

    function _isCollateral(address token) internal view returns (bool) {
        return token == _settlementToken;
    }

    function _requireWETH9IsCollateral() internal view {
        // V_WINAC: WETH9 is not a collateral
        require(_isCollateral(_WETH9), "V_WINAC");
    }

    /// @inheritdoc BaseRelayRecipient
    function _msgSender() internal view override(BaseRelayRecipient, OwnerPausable) returns (address payable) {
        return super._msgSender();
    }

    /// @inheritdoc BaseRelayRecipient
    function _msgData() internal view override(BaseRelayRecipient, OwnerPausable) returns (bytes memory) {
        return super._msgData();
    }
}

