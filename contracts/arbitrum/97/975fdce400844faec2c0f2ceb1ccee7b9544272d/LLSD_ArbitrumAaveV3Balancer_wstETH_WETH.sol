// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.18;

import { BaseTransfersNative } from "./BaseTransfersNative.sol";
import {     WETH9NativeWrapper,     BaseNativeWrapperConfig } from "./WETH9NativeWrapper.sol";
import { SwapPayload } from "./BaseSwap.sol";
import { DefinitiveAssets, IERC20 } from "./DefinitiveAssets.sol";
import {     CoreAccessControlConfig,     CoreSwapConfig,     CoreFeesConfig,     LLSDStrategy,     LLSDStrategyConfig } from "./LLSDStrategy.sol";
import { AaveV3Helper, DataTypes } from "./AaveV3Helper.sol";

// solhint-disable-next-line contract-name-camelcase
contract LLSD_ArbitrumAaveV3Balancer_wstETH_WETH is LLSDStrategy, BaseTransfersNative, WETH9NativeWrapper {
    using DefinitiveAssets for IERC20;

    /// @dev Aave V3 Mainnet Pool Address
    /// @dev https://docs.aave.com/developers/deployed-contracts/v3-mainnet/arbitrum
    address public constant AAVE_V3_POOL = 0x794a61358D6845594F94dc1DB02A252b5b4814aD;

    constructor(
        BaseNativeWrapperConfig memory baseNativeWrapperConfig,
        CoreAccessControlConfig memory coreAccessControlConfig,
        CoreSwapConfig memory coreSwapConfig,
        CoreFeesConfig memory coreFeesConfig,
        address flashloanProviderAddress
    )
        LLSDStrategy(
            coreAccessControlConfig,
            coreSwapConfig,
            coreFeesConfig,
            LLSDStrategyConfig(
                /// @dev STAKING_TOKEN: WETH
                0x82aF49447D8a07e3bd95BD0d56f35241523fBab1,
                /// @dev STAKED_TOKEN: wstETH
                /// @dev https://docs.lido.fi/deployed-contracts/#arbitrum-part
                0x5979D7b546E38E414F7E9822514be443A4800529
            ),
            flashloanProviderAddress
        )
        WETH9NativeWrapper(baseNativeWrapperConfig)
    {
        AaveV3Helper.setEMode(AAVE_V3_POOL, 2);
    }

    function enter(
        uint256 flashloanAmount,
        SwapPayload calldata swapPayload,
        uint256 maxLTV
    ) external onlyWhitelisted stopGuarded nonReentrant enforceMaxLTV(maxLTV) emitEvent(FlashLoanContextType.ENTER) {
        EnterContext memory ctx = EnterContext(flashloanAmount, swapPayload, maxLTV);

        return
            flashloanAmount == 0
                ? _enterContinue(abi.encode(ctx))
                : initiateFlashLoan(
                    STAKING_TOKEN(),
                    flashloanAmount,
                    abi.encode(FlashLoanContextType.ENTER, abi.encode(ctx))
                );
    }

    function exit(
        uint256 flashloanAmount,
        uint256 repayAmount,
        uint256 decollateralizeAmount,
        SwapPayload calldata swapPayload,
        uint256 maxLTV
    ) external onlyWhitelisted stopGuarded nonReentrant enforceMaxLTV(maxLTV) emitEvent(FlashLoanContextType.EXIT) {
        ExitContext memory ctx = ExitContext(flashloanAmount, repayAmount, decollateralizeAmount, swapPayload, maxLTV);

        return
            flashloanAmount == 0
                ? _exitContinue(abi.encode(ctx))
                : initiateFlashLoan(
                    STAKING_TOKEN(),
                    flashloanAmount,
                    abi.encode(FlashLoanContextType.EXIT, abi.encode(ctx))
                );
    }

    function setEMode(uint8 categoryId) external onlyWhitelisted {
        AaveV3Helper.setEMode(AAVE_V3_POOL, categoryId);
    }

    function getDebtAmount() public view override returns (uint256) {
        return AaveV3Helper.getTotalVariableDebt(AAVE_V3_POOL, STAKING_TOKEN());
    }

    function getCollateralToDebtPrice() external view returns (uint256, uint256) {
        return AaveV3Helper.getOraclePriceRatio(AAVE_V3_POOL, STAKING_TOKEN(), STAKED_TOKEN());
    }

    function getCollateralAmount() public view override returns (uint256) {
        return AaveV3Helper.getTotalCollateral(AAVE_V3_POOL, STAKED_TOKEN());
    }

    function getLTV() public view override returns (uint256) {
        return AaveV3Helper.getLTV(AAVE_V3_POOL, address(this));
    }

    function onFlashLoanReceived(
        address, // token
        uint256, // amount
        uint256, // feeAmount
        bytes memory userData
    ) internal override {
        (FlashLoanContextType ctxType, bytes memory data) = abi.decode(userData, (FlashLoanContextType, bytes));

        if (ctxType == FlashLoanContextType.ENTER) {
            return _enterContinue(data);
        }

        if (ctxType == FlashLoanContextType.EXIT) {
            return _exitContinue(data);
        }
    }

    function _enterContinue(bytes memory contextData) internal {
        EnterContext memory context = abi.decode(contextData, (EnterContext));
        address mSTAKED_TOKEN = STAKED_TOKEN();

        // Swap in to staked asset
        if (context.swapPayload.amount > 0) {
            SwapPayload[] memory swapPayloads = new SwapPayload[](1);
            swapPayloads[0] = context.swapPayload;
            _swap(swapPayloads, mSTAKED_TOKEN);
        }

        // Supply dry balance of staked token
        _supply(DefinitiveAssets.getBalance(mSTAKED_TOKEN));

        // Borrow flashloan amount for repayment
        _borrow(context.flashloanAmount);
    }

    function _exitContinue(bytes memory contextData) internal {
        ExitContext memory context = abi.decode(contextData, (ExitContext));

        // Repay debt
        _repay(context.repayAmount);

        // Decollateralize
        _decollateralize(context.decollateralizeAmount);

        // Swap out of staked asset
        if (context.swapPayload.amount > 0) {
            SwapPayload[] memory swapPayloads = new SwapPayload[](1);
            swapPayloads[0] = context.swapPayload;
            _swap(swapPayloads, STAKING_TOKEN());
        }
    }

    function _borrow(uint256 amount) internal override {
        AaveV3Helper.borrow(AAVE_V3_POOL, STAKING_TOKEN(), amount, DataTypes.InterestRateMode.VARIABLE, address(this));
    }

    function _decollateralize(uint256 amount) internal override {
        AaveV3Helper.decollateralize(AAVE_V3_POOL, STAKED_TOKEN(), amount, address(this));
    }

    function _repay(uint256 amount) internal override {
        uint256 debtAmount = getDebtAmount();
        AaveV3Helper.repay(
            AAVE_V3_POOL,
            STAKING_TOKEN(),
            amount > debtAmount ? debtAmount : amount,
            DataTypes.InterestRateMode.VARIABLE,
            address(this)
        );
    }

    function _supply(uint256 amount) internal override {
        AaveV3Helper.supply(AAVE_V3_POOL, STAKED_TOKEN(), amount, address(this));
    }
}

