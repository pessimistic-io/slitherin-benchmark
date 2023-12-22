// SPDX-License-Identifier: UNLICENSED

// Copyright (c) 2023 JonesDAO - All rights reserved
// Jones DAO: https://www.jonesdao.io/

// Check https://docs.jonesdao.io/jones-dao/other/bounty for details on our bounty program.

pragma solidity ^0.8.10;

import {FixedPointMathLib} from "./FixedPointMathLib.sol";
import {CompoundStrategyLib} from "./CompoundStrategyLib.sol";
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
    using CompoundStrategyLib for ICompoundStrategy;

    struct MidEpochInfo {
        ICompoundStrategy compoundStrategy;
        IOptionStrategy optionStrategy;
        ILPVault vault;
        IOption provider;
        IRouter router;
        uint16 epoch;
        uint256 length;
        uint256 toBuyOptions;
        uint256 finalFarm;
        uint256 finalOptions;
    }

    struct PreviewZapInfo {
        IUniswapV2Pair pair;
        address tokenOut;
        uint256 reserveIn;
        uint256 amountDeducted;
        uint256 amountInDeductedFee;
        uint256 priceImpact;
        uint256 estimatedLP;
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
     * @param _oldStrategy Current user's deposited strategy
     * @param _newStrategy New strategy user will be depositing
     * @param _user User that signaled flip
     * @param _targetEpoch User's corresponding flip epoch
     */
    function getFlipSignal(
        IRouter.OptionStrategy _oldStrategy,
        IRouter.OptionStrategy _newStrategy,
        address _user,
        uint16 _targetEpoch,
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
    function getWithdrawalSignal(IRouter.OptionStrategy _strategy, uint16 _targetEpoch, address _user, address lp)
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
    function getEpochData(uint16 _epoch, address lp) public view returns (ICompoundStrategy.Epoch memory) {
        return metavault[lp].compoundStrategy.epochData(_epoch);
    }

    /**
     * @return Returns the number of the current epoch
     */
    function currentEpoch(address lp) public view returns (uint16) {
        return metavault[lp].compoundStrategy.currentEpoch();
    }

    /**
     * @return Returns the withdrawal incentive paid by users
     */
    function getRetentionIncentive(address lp) public view returns (uint256) {
        (, uint256 withdrawRetention,) = metavault[lp].router.incentives();
        return withdrawRetention;
    }

    /**
     * @param lp Address of the underlying LP token of given metavault.
     * @return addresses of the desired metavault
     */
    function getMetavault(address lp) public view returns (Addresses memory) {
        return metavault[lp];
    }

    function previewDepositZap(
        address lp,
        address tokenIn,
        uint256 amountIn,
        IRouter.OptionStrategy _strategy,
        bytes[] calldata optionOrders
    ) public view returns (uint256) {
        PreviewZapInfo memory info;

        info.pair = IUniswapV2Pair(lp);

        if (tokenIn == info.pair.token0()) {
            info.tokenOut = info.pair.token1();
            (uint112 reserveA,,) = info.pair.getReserves();
            info.reserveIn = reserveA;
        } else {
            info.tokenOut = info.pair.token0();
            (, uint112 reserveB,) = info.pair.getReserves();
            info.reserveIn = reserveB;
        }

        // Since we will need to convert half of the amountIn to the other LP tokens asset
        // we simualate a swap and adding liquidity using the received amount so it accounts for slippage + fees
        info.amountDeducted = AssetsPricing.getAmountOut(lp, amountIn, tokenIn, info.tokenOut);

        // Without price impact or slippage
        info.amountInDeductedFee = amountIn - ((amountIn * 3) / 10000);

        // Calculate price impact 18 decimals
        info.priceImpact = (info.amountInDeductedFee * PRECISION) / (info.reserveIn + info.amountInDeductedFee);

        info.estimatedLP = AssetsPricing.tokenToLiquidity(lp, info.tokenOut, info.amountDeducted);

        // Consider price increase by purchasing amountIn worth of tokenOut in the final LP amount
        if (info.priceImpact > 0) {
            info.estimatedLP += (info.estimatedLP * info.priceImpact / PRECISION);
        }

        return previewDeposit(_strategy, info.estimatedLP, lp, optionOrders);
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
     * @return Amount of incentive retention
     */
    function previewRedeem(IRouter.OptionStrategy _strategy, uint256 _amount, address lp)
        public
        view
        returns (uint256, uint256)
    {
        Addresses memory addresses = metavault[lp];
        (uint16 epoch, uint256 endTime, uint256 sharesWithPenalty) =
            addresses.compoundStrategy.penalty(_amount, _strategy);

        (address incentiveReceiver, uint256 retention,) = addresses.router.incentives();

        IOptionStrategy _optionStrategy = addresses.optionStrategy;
        uint256 assets;

        if (
            _strategy == IRouter.OptionStrategy.CRAB || endTime > 0 || epoch == 0
                || (_optionStrategy.executedStrategy(epoch, _strategy) && _optionStrategy.borrowedLP(_strategy) == 0)
        ) {
            assets = vaultAddresses(_strategy, lp).previewRedeem(_amount);
        } else {
            assets = vaultAddresses(_strategy, lp).previewRedeem(sharesWithPenalty);
        }

        if (incentiveReceiver != address(0)) {
            retention = assets.mulDivDown(retention, BASIS);
        }

        return (assets - retention, retention);
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
    function userNextEpochDeposit(address _user, IRouter.OptionStrategy _strategy, uint16 _epoch, address lp)
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
    function previewDeposit(
        IRouter.OptionStrategy _strategy,
        uint256 _amount,
        address lp,
        bytes[] calldata optionOrders
    ) public view returns (uint256) {
        Addresses memory addresses = metavault[lp];

        // Get current epoch and end time and option risks
        (uint16 epoch, uint256 endTime, uint256 optionBullRisk, uint256 optionBearRisk) =
            addresses.compoundStrategy.epochEndTimeAndOptionRisk();

        if (
            _strategy == IRouter.OptionStrategy.CRAB || endTime > 0 || epoch == 0
                || (
                    addresses.optionStrategy.executedStrategy(epoch, _strategy)
                        && addresses.optionStrategy.borrowedLP(_strategy) == 0
                )
        ) {
            return vaultAddresses(_strategy, lp).previewDeposit(_amount);
        } else if (!addresses.optionStrategy.executedStrategy(epoch, _strategy)) {
            if (_strategy == IRouter.OptionStrategy.BULL) {
                _amount = _amount - _amount.mulDivDown(optionBullRisk, BASIS);
            } else {
                _amount = _amount - _amount.mulDivDown(optionBearRisk, BASIS);
            }
            return vaultAddresses(_strategy, lp).previewDeposit(_amount);
        } else {
            return _midEpochPreviewDeposit(addresses, _strategy, _amount, lp, optionOrders);
        }
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
        emit SetAddresses(msg.sender, lp, _newAddresses);
    }

    /* ============== Private ================ */

    function _midEpochPreviewDeposit(
        Addresses memory _addresses,
        IRouter.OptionStrategy _strategy,
        uint256 _assets,
        address lp,
        bytes[] calldata optionOrders
    ) private view returns (uint256) {
        MidEpochInfo memory info;

        info.compoundStrategy = _addresses.compoundStrategy;
        info.epoch = info.compoundStrategy.currentEpoch();
        info.optionStrategy = _addresses.optionStrategy;
        info.router = _addresses.router;

        if (_strategy == IRouter.OptionStrategy.BULL) {
            info.vault = ILPVault(info.compoundStrategy.getVaults()[0]);
        } else if (_strategy == IRouter.OptionStrategy.BEAR) {
            info.vault = ILPVault(info.compoundStrategy.getVaults()[1]);
        }

        if (_strategy == IRouter.OptionStrategy.BULL) {
            info.toBuyOptions = _assets.mulDivDown(info.compoundStrategy.epochData(info.epoch).optionBullRisk, BASIS);
        } else {
            info.toBuyOptions = _assets.mulDivDown(info.compoundStrategy.epochData(info.epoch).optionBearRisk, BASIS);
        }

        if (info.toBuyOptions > 0) {
            info.provider = info.optionStrategy.defaultAdapter(_strategy);

            info.length = optionOrders.length;

            for (uint256 i; i < info.length; ++i) {
                // Get information about the strikes from given info (providers, epoch)
                IOptionStrategy.OptionOverpayAndData memory overpayAndData = info.optionStrategy.deltaPrice(
                    info.epoch, info.toBuyOptions, _strategy, optionOrders[i], address(info.provider)
                );
                //  Will be deducted from user assets.
                if (!overpayAndData.isOverpaying) {
                    info.finalFarm = info.finalFarm + overpayAndData.toFarm;
                }

                uint256 toBuyOptions =
                    overpayAndData.toBuyOptions.mulDivDown(overpayAndData.collateralPercentage, BASIS);
                uint256 toFarm = overpayAndData.toBuyOptions - toBuyOptions;

                if (overpayAndData.cost > 0) {
                    info.finalOptions = info.finalOptions + toBuyOptions;
                    if (toFarm > 0) {
                        info.finalFarm = info.finalFarm + toFarm + toFarm.mulDivUp(info.router.premium(), BASIS);
                    }
                } else {
                    info.finalFarm = info.finalFarm + toBuyOptions + toBuyOptions.mulDivUp(info.router.premium(), BASIS);
                }
            }

            _assets = _assets - info.finalFarm - info.finalOptions;
        }

        return info.vault.previewDeposit(_assets);
    }

    /* -------------------------------------------------------------------------- */
    /*                                   EVENTS                                   */
    /* -------------------------------------------------------------------------- */

    event SetAddresses(address indexed who, address indexed lp, Addresses _newAddresses);

    /* -------------------------------------------------------------------------- */
    /*                                    ERRORS                                  */
    /* -------------------------------------------------------------------------- */

    error ZeroAddress();
}

