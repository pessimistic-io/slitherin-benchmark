// SPDX-License-Identifier: UNLICENSED

// Copyright (c) 2023 JonesDAO - All rights reserved
// Jones DAO: https://www.jonesdao.io/

// Check https://docs.jonesdao.io/jones-dao/other/bounty for details on our bounty program.

pragma solidity ^0.8.10;

import {FixedPointMathLib} from "./FixedPointMathLib.sol";
import {UpgradeableOperable} from "./UpgradeableOperable.sol";
import {ICompoundStrategy} from "./CompoundStrategy.sol";
import {IOptionStrategy} from "./IOptionStrategy.sol";
import {ILPVault} from "./ILPVault.sol";
import {IOption} from "./IOption.sol";
import {IViewer} from "./IViewer.sol";
import {IRouter} from "./IRouter.sol";
import {IUniswapV2Pair} from "./IUniswapV2Pair.sol";
import {AssetsPricing} from "./AssetsPricing.sol";

contract Viewer is IViewer, UpgradeableOperable {
    using FixedPointMathLib for uint256;

    struct MidEpochInfo {
        ICompoundStrategy _compoundStrategy;
        IOptionStrategy _optionStrategy;
        ILPVault vault;
        IOption.OPTION_TYPE optionType;
        IOption provider;
        uint256 toBuyOptions;
        uint256 epoch;
        uint256 finalAssets;
        uint256 availableLiquidity;
        uint256 amountInCollateralToken;
        uint256 toFarm;
        uint256 toFarmWithPremium;
    }

    // 100%
    uint256 public constant BASIS = 1e12;
    uint256 public constant PRECISION = 1e18;
    address public constant WETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;

    // LP address of metavault -> struct containing its contracts.
    mapping(address => Addresses) public metavault;

    function initialize() public initializer {
        __Governable_init(msg.sender);
    }

    /**
     *
     * @param _oldStrategy Current user's deposited strategy
     * @param _newStrategy New strategy user will be depositing
     * @param _user User that signaled flip
     * @param _targetEpoch User's corresponding flip epoch
     */
    function getFlipSignal(
        IRouter.OptionStrategy _oldStrategy,
        IRouter.OptionStrategy _newStrategy,
        address _user,
        uint256 _targetEpoch,
        address lp
    ) public view returns (IRouter.FlipSignal memory) {
        return metavault[lp].router.getFlipSignal(_user, _targetEpoch, _oldStrategy, _newStrategy);
    }

    /**
     * @param _strategy Bull/Bear/Crab
     * @param _targetEpoch Epoch the user will get his withdrawal
     * @param _user Owner of the assets
     * @return Struct with the user's signal information
     */
    function getWithdrawalSignal(IRouter.OptionStrategy _strategy, uint256 _targetEpoch, address _user, address lp)
        public
        view
        returns (IRouter.WithdrawalSignal memory)
    {
        return metavault[lp].router.getWithdrawSignal(_user, _targetEpoch, _strategy);
    }

    /**
     * @notice Get the vaults addresses
     * @param _strategy Bull/Bear/Crab
     * @return returns the corresponding vault to given strategy type
     */
    function vaultAddresses(IRouter.OptionStrategy _strategy, address lp) public view returns (ILPVault) {
        if (_strategy == IRouter.OptionStrategy.BULL) {
            return metavault[lp].compoundStrategy.getVaults()[0];
        } else if (_strategy == IRouter.OptionStrategy.BEAR) {
            return metavault[lp].compoundStrategy.getVaults()[1];
        }

        return metavault[lp].compoundStrategy.getVaults()[2];
    }

    /**
     * @return Returns the current Compound Strategy's epoch struct containing data
     */
    function getEpochData(uint256 _epoch, address lp) public view returns (ICompoundStrategy.Epoch memory) {
        return metavault[lp].compoundStrategy.epochData(_epoch);
    }

    /**
     * @return Returns the number of the current epoch
     */
    function currentEpoch(address lp) public view returns (uint256) {
        return metavault[lp].compoundStrategy.currentEpoch();
    }

    /**
     * @return Returns the withdrawal incentive paid by users
     */
    function getRetentionIncentive(address lp) public view returns (uint256) {
        return metavault[lp].compoundStrategy.retentionIncentive();
    }

    /**
     * @param lp Address of the underlying LP token of given metavault.
     * @return addresses of the desired metavault
     */
    function getMetavault(address lp) public view returns (Addresses memory) {
        return metavault[lp];
    }

    function previewDepositZap(address lp, address tokenIn, uint256 amountIn, IRouter.OptionStrategy _strategy)
        public
        view
        returns (uint256)
    {
        IUniswapV2Pair pair = IUniswapV2Pair(lp);
        uint256 amountDeducted;

        address tokenOut;
        //= tokenIn == pair.token0() ? pair.token1() : pair.token0();

        uint256 reserveIn;

        if (tokenIn == pair.token0()) {
            tokenOut = pair.token1();
            (uint112 reserveA,,) = pair.getReserves();
            reserveIn = reserveA;
        } else {
            tokenOut = pair.token0();
            (, uint112 reserveB,) = pair.getReserves();
            reserveIn = reserveB;
        }

        // Since we will need to convert half of the amountIn to the other LP tokens asset
        // we simualate a swap and adding liquidity using the received amount so it accounts for slippage + fees
        amountDeducted = AssetsPricing.getAmountOut(lp, amountIn, tokenIn, tokenOut);

        // Without price impact or slippage
        uint256 amountInDeductedFee = amountIn - ((amountIn * 3) / 10000);

        // Calculate price impact 18 decimals
        uint256 priceImpact = (amountInDeductedFee * PRECISION) / (reserveIn + amountInDeductedFee);

        uint256 estimatedLP = AssetsPricing.tokenToLiquidity(lp, tokenOut, amountDeducted);

        // Consider price increase by purchasing amountIn worth of tokenOut in the final LP amount
        if (priceImpact > 0) {
            estimatedLP += (estimatedLP * priceImpact / PRECISION);
        }

        return previewDeposit(_strategy, estimatedLP, lp);
    }

    /* =============== ERC-4626 =============== */

    /**
     * @param _strategy Bull/Bear/Crab
     * @return Amount of assets of the given vault
     */
    function totalAssets(IRouter.OptionStrategy _strategy, address lp) public view returns (uint256) {
        return vaultAddresses(_strategy, lp).totalAssets();
    }

    /**
     * @param _strategy Bull/Bear/Crab
     * @param _user User that owns the shares
     * @return Amount of shares for given user
     */
    function balanceOf(IRouter.OptionStrategy _strategy, address _user, address lp) public view returns (uint256) {
        return vaultAddresses(_strategy, lp).balanceOf(_user);
    }

    /**
     * @param _strategy Bull/Bear/Crab
     * @param _amount Amount of shares
     * @return Amount of assets that will be received
     */
    function previewRedeem(IRouter.OptionStrategy _strategy, uint256 _amount, address lp)
        public
        view
        returns (uint256)
    {
        return vaultAddresses(_strategy, lp).previewRedeem(_amount);
    }

    /**
     * @notice Get the amount of deposits scheduled to happen next epoch
     * @param _strategy Deposits for given strategy
     * @return Amount of assets that will be deposited
     */
    function nextEpochDeposits(IRouter.OptionStrategy _strategy, address lp) public view returns (uint256) {
        return metavault[lp].router.nextEpochDeposits(_strategy);
    }

    // @notice Total amount of deposits scheduled to happen next epoch
    function nextEpochDepositsTotal(address lp) public view returns (uint256) {
        return metavault[lp].router.nextEpochDeposits(IRouter.OptionStrategy.BULL)
            + metavault[lp].router.nextEpochDeposits(IRouter.OptionStrategy.BEAR);
    }

    /**
     * @notice Amount of assets user has scheduled to be deposited next epoch
     * @param _user User that has performed a next epoch deposit
     * @param _strategy Strategy user has deposited
     * @param _epoch The user assets will be effectively deposited at _epoch + 1
     * @return Amount of assets that will be deposited
     */
    function userNextEpochDeposit(address _user, IRouter.OptionStrategy _strategy, uint256 _epoch, address lp)
        public
        view
        returns (uint256)
    {
        return metavault[lp].router.userNextEpochDeposits(_user, _epoch, _strategy);
    }

    /**
     * @param _strategy Bull/Bear/Crab
     * @param _amount Amount of assets
     * @return Amount of shares that will be received
     */
    function previewDeposit(IRouter.OptionStrategy _strategy, uint256 _amount, address lp)
        public
        view
        returns (uint256)
    {
        Addresses memory addresses = metavault[lp];
        ICompoundStrategy strategy = addresses.compoundStrategy;

        if (strategy.epochData(strategy.currentEpoch()).endTime != 0 && _strategy != IRouter.OptionStrategy.CRAB) {
            return _midEpochPreviewDeposit(addresses, _strategy, _amount, lp);
        }

        return vaultAddresses(_strategy, lp).previewDeposit(_amount);
    }

    /* =============== Operator or Governor =============== */

    /**
     * @param _newAddresses update Metavaults V2 contracts
     */
    function setAddresses(address lp, Addresses memory _newAddresses) external onlyGovernorOrOperator {
        if (lp == address(0)) {
            revert ZeroAddress();
        }
        metavault[lp] = _newAddresses;
    }

    /* ============== Private ================ */

    function _midEpochPreviewDeposit(
        Addresses memory _addresses,
        IRouter.OptionStrategy _strategy,
        uint256 _assets,
        address lp
    ) private view returns (uint256) {
        MidEpochInfo memory info;
        info._compoundStrategy = _addresses.compoundStrategy;
        info.epoch = info._compoundStrategy.currentEpoch();
        info._optionStrategy = _addresses.optionStrategy;
        info.vault;

        if (_strategy == IRouter.OptionStrategy.BULL) {
            info.vault = ILPVault(_addresses.compoundStrategy.getVaults()[0]);
        } else if (_strategy == IRouter.OptionStrategy.BEAR) {
            info.vault = ILPVault(_addresses.compoundStrategy.getVaults()[1]);
        }

        // Final amounts that will be converted to shares
        info.finalAssets = _assets;

        if (_strategy == IRouter.OptionStrategy.BULL) {
            info.optionType = IOption.OPTION_TYPE.CALLS;
            info.toBuyOptions = _assets.mulDivDown(info._compoundStrategy.epochData(info.epoch).optionBullRisk, BASIS);
        } else {
            info.optionType = IOption.OPTION_TYPE.PUTS;
            info.toBuyOptions = _assets.mulDivDown(info._compoundStrategy.epochData(info.epoch).optionBearRisk, BASIS);
        }

        // If we are in the gap between startEpoch and ExecuteStrategy, just reduce optionRisk
        // since no options are bought yet
        if (!info._optionStrategy.executedStrategy(info.epoch, _strategy)) {
            return info.vault.previewDeposit(_assets - info.toBuyOptions);
        }

        info.provider = info._optionStrategy.dopexAdapter(info.optionType);

        // Compare current prices with prices paid in first strategy exec
        IOptionStrategy.DifferenceAndOverpaying[] memory _diffAndOverpaying =
            info._optionStrategy.deltaPrice(info.epoch, info.toBuyOptions, info.provider);

        for (uint256 i; i < _diffAndOverpaying.length; ++i) {
            //  Will be deducted from user assets.
            if (!_diffAndOverpaying[i].isOverpaying) {
                info.finalAssets - _diffAndOverpaying[i].toFarm;
            }

            info.availableLiquidity = info.provider.getAvailableOptions(_diffAndOverpaying[i].strikePrice);

            info.amountInCollateralToken = info.provider.lpToCollateral(lp, _diffAndOverpaying[i].collateral).mulDivDown(
                _addresses.router.slippage(), BASIS
            );

            if (info.availableLiquidity > info.amountInCollateralToken) {
                // If there is liquidity, we are breaking `amountInCollateral` amount of LP and buy options.
                info.finalAssets - _diffAndOverpaying[i].collateral;
            } else {
                // Will buy max possible (availableLiquidity)
                info.toFarm = _diffAndOverpaying[i].collateral - info.availableLiquidity;
                // The not used amount will be increased premium% and be sent to farm
                info.toFarmWithPremium = info.toFarm + info.toFarm.mulDivDown(_addresses.router.premium(), BASIS);

                info.finalAssets - info.availableLiquidity - info.toFarmWithPremium;
            }
        }

        return info.vault.previewDeposit(info.finalAssets);
    }

    /* =============== Custom Errors =============== */

    error ZeroAddress();
}

