// SPDX-License-Identifier: UNLICENSED

// Copyright (c) 2023 JonesDAO - All rights reserved
// Jones DAO: https://www.jonesdao.io/

// Check https://docs.jonesdao.io/jones-dao/other/bounty for details on our bounty program.

pragma solidity ^0.8.10;

import {FixedPointMathLib} from "./FixedPointMathLib.sol";
import {IERC20} from "./IERC20.sol";
import {UpgradeableOperableKeepable} from "./UpgradeableOperableKeepable.sol";
import {IRouter} from "./IRouter.sol";
import {ILPVault} from "./ILPVault.sol";
import {IOptionStrategy} from "./IOptionStrategy.sol";
import {ICompoundStrategy, IFarm} from "./ICompoundStrategy.sol";

contract CompoundStrategy is ICompoundStrategy, UpgradeableOperableKeepable {
    using FixedPointMathLib for uint256;

    /* -------------------------------------------------------------------------- */
    /*                                  VARIABLES                                 */
    /* -------------------------------------------------------------------------- */

    // @notice Internal representation of 100%
    uint256 private constant BASIS = 1e12;

    // @notice Current system epoch
    uint16 public currentEpoch;

    // @notice Max % of projected farm rewards used to buy options. Backstop for safety measures
    uint256 private maxRisk;

    // @dev Mapping of Epoch number -> Epoch struct that contains data about a given epoch
    mapping(uint16 => Epoch) private epoch;

    // @notice Each vault has its own balance
    mapping(IRouter.OptionStrategy => uint256) private vaultBalance;

    // @notice The LP token for this current Metavault
    IERC20 public lpToken;

    // @notice Product router
    IRouter private router;

    // @notice Vaults for the different strategies
    ILPVault[] public vaults;

    // @notice Lp farm adapter (eg: MinichefV2 adapter)
    IFarm public farm;

    // @notice The OptionStrategy contract that manages purchasing/settling options
    IOptionStrategy private option;

    /* -------------------------------------------------------------------------- */
    /*                                    INIT                                    */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice Initializes CompoundStrategy transparent upgradeable proxy
     * @param _farm Lp farm adapter (eg: MinichefV2 adapter)
     * @param _option The OptionStrategy contract that manages purchasing/settling options
     * @param _router Product router
     * @param _vaults Vaults for the different strategies
     * @param _lpToken The LP token for this current Metavault
     * @param _maxRisk Max % of projected farm rewards used to buy options. Backstop for safety measuresco
     */
    function initializeCmpStrategy(
        IFarm _farm,
        IOptionStrategy _option,
        IRouter _router,
        ILPVault[] memory _vaults,
        address _lpToken,
        uint256 _maxRisk
    ) external initializer {
        __Governable_init(msg.sender);

        IERC20 lpToken_ = IERC20(_lpToken);

        lpToken = IERC20(_lpToken);

        maxRisk = _maxRisk;

        router = _router;

        vaults.push(_vaults[0]);
        vaults.push(_vaults[1]);
        vaults.push(_vaults[2]);

        farm = _farm;
        option = _option;

        // Farm approve
        lpToken_.approve(address(_farm), type(uint256).max);

        // Option approve
        lpToken_.approve(address(_option), type(uint256).max);
    }

    /* -------------------------------------------------------------------------- */
    /*                                 ONLY OPERATOR                              */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice Handles LPs deposits accountability and staking
     * @param _amount Amount of LP tokens being deposited
     * @param _type Strategy which balance will be updated
     * @param _nextEpoch signal to not increase the balance of the vault immidiatly.
     */
    function deposit(uint256 _amount, IRouter.OptionStrategy _type, bool _nextEpoch) external onlyOperator {
        if (!_nextEpoch) {
            vaultBalance[_type] += _amount;
        }

        lpToken.approve(address(farm), _amount);

        // Stake the LP token
        farm.stake(_amount);

        // Send dust reward token to farm
        IERC20 rewardToken = farm.rewardToken();
        if (address(rewardToken) != address(0)) {
            uint256 rewardBalance = rewardToken.balanceOf(address(this));
            if (rewardBalance > 0) {
                rewardToken.transfer(address(farm), rewardBalance);
            }
        }
    }

    /**
     * @notice Withdraw LP assets.
     * @param _amountWithPenalty Amount to unstake
     * @param _receiver Who will receive the LP token
     */
    function instantWithdraw(uint256 _amountWithPenalty, IRouter.OptionStrategy _type, address _receiver)
        external
        onlyOperator
    {
        vaultBalance[_type] = vaultBalance[_type] > _amountWithPenalty ? vaultBalance[_type] - _amountWithPenalty : 0;
        farm.unstake(_amountWithPenalty, _receiver);
    }

    /* -------------------------------------------------------------------------- */
    /*                                  ONLY KEEPER                               */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice Auto compounds all the farming rewards.
     */
    function autoCompound() external onlyOperatorOrKeeper {
        _autoCompound();
    }

    /**
     * @notice Start new epoch.
     */
    function startEpoch(uint64 epochExpiry, uint64 optionBullRisk, uint64 optionBearRisk)
        external
        onlyOperatorOrKeeper
    {
        // Stack too deep
        StartEpochInfo memory epochInfo;

        // Make sure last epoch finished
        // Only check if its not first epoch from this product
        epochInfo.epoch = currentEpoch;
        if (epoch[epochInfo.epoch].endTime == 0 && epochInfo.epoch > 0) {
            revert EpochOngoing();
        }

        // Next Epoch!
        unchecked {
            ++currentEpoch;
        }

        epochInfo.epoch = currentEpoch;

        // Review option risk
        if (optionBullRisk > maxRisk || optionBearRisk > maxRisk) {
            revert OutOfRange();
        }

        // Save the ratios (for APY)
        epochInfo.bullRatio = vaults[0].previewRedeem(BASIS);
        epochInfo.bearRatio = vaults[1].previewRedeem(BASIS);
        epochInfo.crabRatio = vaults[2].previewRedeem(BASIS);

        epochInfo.thisAddress = address(this);

        IERC20 _lpToken = lpToken;

        epochInfo.currentLPBalance = _lpToken.balanceOf(epochInfo.thisAddress);
        epochInfo.farmBalance = farm.balance();

        epochInfo.initialBalanceSnapshot = epochInfo.farmBalance + epochInfo.currentLPBalance;

        // Get total and indiviual vault balance (internal accounting)
        epochInfo.bullAssets = vaultBalance[IRouter.OptionStrategy.BULL];
        epochInfo.bearAssets = vaultBalance[IRouter.OptionStrategy.BEAR];
        epochInfo.crabAssets = vaultBalance[IRouter.OptionStrategy.CRAB];
        epochInfo.totalBalance = epochInfo.bullAssets + epochInfo.bearAssets + epochInfo.crabAssets;

        // Get how much LP belongs to strategy, then apply bull/bear risk
        epochInfo.bullAmount = epochInfo.totalBalance > 0
            ? epochInfo.initialBalanceSnapshot.mulDivDown(epochInfo.bullAssets, epochInfo.totalBalance).mulDivDown(
                optionBullRisk, BASIS
            )
            : 0;

        // Get how much LP belongs to strategy, then apply bull/bear risk
        epochInfo.bearAmount = epochInfo.totalBalance > 0
            ? epochInfo.initialBalanceSnapshot.mulDivDown(epochInfo.bearAssets, epochInfo.totalBalance).mulDivDown(
                optionBullRisk, BASIS
            )
            : 0;

        // Sum amounts to get how much LP are going to be broken in order to buy options
        epochInfo.toOptions = epochInfo.bullAmount + epochInfo.bearAmount;

        // If we do not have enough LP tokens to buy desired OptionAmount, we unstake some
        if (epochInfo.currentLPBalance < epochInfo.toOptions) {
            if (epochInfo.farmBalance == 0) {
                revert InsufficientFunds();
            }

            farm.unstake(epochInfo.toOptions - epochInfo.currentLPBalance, epochInfo.thisAddress);
        }

        // Reduce assets used to purchase options from vault balances
        vaultBalance[IRouter.OptionStrategy.BULL] = vaultBalance[IRouter.OptionStrategy.BULL] - epochInfo.bullAmount;
        vaultBalance[IRouter.OptionStrategy.BEAR] = vaultBalance[IRouter.OptionStrategy.BEAR] - epochInfo.bearAmount;

        // Deposit LP amount to Option Strategy
        if (epochInfo.toOptions > 0) {
            _lpToken.transfer(address(option), epochInfo.toOptions);
            option.deposit(epochInfo.epoch, epochInfo.toOptions, epochInfo.bullAmount, epochInfo.bearAmount);
        }
        // Balance after transfer to buy options
        epochInfo.currentLPBalance = _lpToken.balanceOf(epochInfo.thisAddress);

        // Stake whats left
        if (epochInfo.currentLPBalance > 0) {
            farm.stake(epochInfo.currentLPBalance);
        }

        uint64 epochInit = uint64(block.timestamp);

        epoch[epochInfo.epoch] = Epoch(
            epochInit,
            epochExpiry,
            0,
            optionBullRisk,
            optionBearRisk,
            uint128(epochInfo.bullRatio),
            uint128(epochInfo.bearRatio),
            uint128(epochInfo.crabRatio),
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0
        );

        emit StartEpoch(
            epochInfo.epoch,
            epochInit,
            epochExpiry,
            epochInfo.toOptions,
            epochInfo.bullAssets,
            epochInfo.bearAssets,
            epochInfo.crabAssets
        );
    }

    /**
     * @notice Finish current epoch.
     */
    function endEpoch() external onlyOperatorOrKeeper {
        _autoCompound();

        // Stack too deep
        GeneralInfo memory generalInfo;

        generalInfo.currentEpoch = currentEpoch;
        generalInfo.endTime = block.timestamp;
        generalInfo.epochData = epoch[generalInfo.currentEpoch];

        // Make sure Epoch has ended
        if (generalInfo.endTime < generalInfo.epochData.virtualEndTime) {
            revert EpochOngoing();
        }
        // Load to memory to save some casts
        generalInfo.thisAddress = address(this);
        generalInfo.routerAddress = address(router);

        generalInfo.bullVault = vaults[0];
        generalInfo.bearVault = vaults[1];
        generalInfo.crabVault = vaults[2];

        generalInfo.router = router;
        generalInfo.lpToken = lpToken;

        generalInfo.bullStrat = IRouter.OptionStrategy.BULL;
        generalInfo.bearStrat = IRouter.OptionStrategy.BEAR;
        generalInfo.crabStrat = IRouter.OptionStrategy.CRAB;

        // Flip
        FlipInfo memory flipInfo = _flip(generalInfo);

        // Withdraw Signals

        WithdrawInfo memory withdrawInfo = _withdraw(generalInfo);

        // Flip & Withdraw Rates

        flipInfo.bullToBearRate =
            flipInfo.bullToBear > 0 ? flipInfo.bullToBearShares.mulDivDown(1e30, flipInfo.bullToBear) : 0;
        flipInfo.bullToCrabRate =
            flipInfo.bullToCrab > 0 ? flipInfo.bullToCrabShares.mulDivDown(1e30, flipInfo.bullToCrab) : 0;
        flipInfo.bearToBullRate =
            flipInfo.bearToBull > 0 ? flipInfo.bearToBullShares.mulDivDown(1e30, flipInfo.bearToBull) : 0;
        flipInfo.bearToCrabRate =
            flipInfo.bearToCrab > 0 ? flipInfo.bearToCrabShares.mulDivDown(1e30, flipInfo.bearToCrab) : 0;
        flipInfo.crabToBullRate =
            flipInfo.crabToBull > 0 ? flipInfo.crabToBullShares.mulDivDown(1e30, flipInfo.crabToBull) : 0;
        flipInfo.crabToBearRate =
            flipInfo.crabToBear > 0 ? flipInfo.crabToBearShares.mulDivDown(1e30, flipInfo.crabToBear) : 0;

        withdrawInfo.withdrawBullRate = withdrawInfo.bullShares > 0
            ? (withdrawInfo.bullAssets - withdrawInfo.bullRetention).mulDivDown(BASIS, withdrawInfo.bullShares)
            : 0;
        withdrawInfo.withdrawBearRate = withdrawInfo.bearShares > 0
            ? (withdrawInfo.bearAssets - withdrawInfo.bearRetention).mulDivDown(BASIS, withdrawInfo.bearShares)
            : 0;

        // Next Epoch Deposits

        DepositInfo memory depositInfo = _deposit(generalInfo);

        // Update router accounting (refresh epoch)
        generalInfo.router.executeFinishEpoch();

        epoch[currentEpoch] = Epoch(
            generalInfo.epochData.startTime,
            generalInfo.epochData.virtualEndTime,
            uint64(generalInfo.endTime),
            generalInfo.epochData.optionBullRisk,
            generalInfo.epochData.optionBearRisk,
            generalInfo.epochData.initialBullRatio,
            generalInfo.epochData.initialBearRatio,
            generalInfo.epochData.initialCrabRatio,
            uint128(withdrawInfo.withdrawBullRate),
            uint128(withdrawInfo.withdrawBearRate),
            uint128(flipInfo.bullToBearRate),
            uint128(flipInfo.bullToCrabRate),
            uint128(flipInfo.bearToBullRate),
            uint128(flipInfo.bearToCrabRate),
            uint128(flipInfo.crabToBullRate),
            uint128(flipInfo.crabToBearRate),
            uint128(depositInfo.depositBullRate),
            uint128(depositInfo.depositBearRate),
            uint128(generalInfo.bullVault.previewRedeem(BASIS)),
            uint128(generalInfo.bearVault.previewRedeem(BASIS)),
            uint128(generalInfo.crabVault.previewRedeem(BASIS))
        );

        emit EndEpoch(generalInfo.currentEpoch, generalInfo.endTime, withdrawInfo.totalSignals, withdrawInfo.retention);
    }

    /* -------------------------------------------------------------------------- */
    /*                                     VIEW                                   */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice Get epoch Data.
     */
    function epochData(uint16 _number) external view returns (Epoch memory) {
        return epoch[_number];
    }

    /**
     * @notice Get the three strategy Vaults; 0 => BULL, 1 => BEAR, 2 => CRAB
     */
    function getVaults() external view returns (ILPVault[] memory) {
        return vaults;
    }

    /**
     * @notice Get LP Vault Assets, overall LP for a Vault.
     */
    function vaultAssets(IRouter.OptionStrategy _type) external view returns (uint256) {
        if (_type != IRouter.OptionStrategy.CRAB) {
            // get pnl over lp that was spend to bought options
            try option.optionPosition(currentEpoch, _type) returns (uint256 pnl) {
                // also add amount of LP that was spend to bought options and pending farm rewards
                return vaultBalance[_type] + _vaultPendingRewards(_type) + pnl + option.borrowedLP(_type);
            } catch {
                return vaultBalance[_type] + _vaultPendingRewards(_type) + option.borrowedLP(_type);
            }
        } else {
            return vaultBalance[_type] + _vaultPendingRewards(_type);
        }
    }

    function getVaultBalance(IRouter.OptionStrategy _type) external view returns (uint256) {
        return vaultBalance[_type];
    }

    /* -------------------------------------------------------------------------- */
    /*                                 ONLY GOVERNOR                              */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice Update Max Option Risk
     */
    function updateRisk(uint256 _maxRisk) external onlyGovernor {
        maxRisk = _maxRisk;
    }

    /**
     * @notice Update Router
     */
    function updateRouter(IRouter _router) external onlyGovernor {
        router = _router;
    }

    /**
     * @notice Update Option Strategy
     */
    function updateOption(address _option) external onlyGovernor {
        IERC20 _lpToken = lpToken;
        _lpToken.approve(address(option), 0);
        // New Option
        option = IOptionStrategy(_option);
        _lpToken.approve(_option, type(uint256).max);
    }

    /**
     * @notice Update Farm adapter
     */
    function updateFarm(address _farm) external onlyGovernor {
        farm.exit();
        lpToken.approve(address(farm), 0);
        // New Farm
        farm = IFarm(_farm);
        lpToken.approve(_farm, type(uint256).max);
        farm.stake(lpToken.balanceOf(address(this)));
    }

    /**
     * @notice Moves assets from the strategy to `_to`
     * @param _to An array of addresses were the tokens will move out from the strategy
     * @param _asset An array of IERC20 compatible tokens to move out from the strategy
     * @param _withdrawNative `true` if we want to move the native asset from the strategy
     */
    function emergencyWithdraw(address _to, IERC20 _asset, bool _withdrawNative) external onlyGovernor {
        uint256 nativeBalance = address(this).balance;

        // Nothing else to do
        if (_withdrawNative && nativeBalance > 0) {
            // Transfer the native currency
            (bool sent,) = payable(_to).call{value: nativeBalance}("");
            if (!sent) {
                revert();
            }

            emit EmergencyWithdrawal(msg.sender, _to, IERC20(address(0)), nativeBalance);
        } else {
            uint256 assetBalance = _asset.balanceOf(address(this));

            if (assetBalance > 0) {
                // Transfer the ERC20 tokens
                _asset.transfer(_to, assetBalance);
            }

            emit EmergencyWithdrawal(msg.sender, _to, _asset, assetBalance);
        }
    }

    /* -------------------------------------------------------------------------- */
    /*                                     PRIVATE                                */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice Get Vault proportional pending rewards from farm.
     */
    function _vaultPendingRewards(IRouter.OptionStrategy _type) private view returns (uint256) {
        try farm.pendingRewardsToLP() returns (uint256 pendingRewards) {
            return _vaultPortion(pendingRewards, _type);
        } catch {
            return 0;
        }
    }

    /**
     * @notice Given an specific amount, return the proportion for a specific vault.
     */
    function _vaultPortion(uint256 amount, IRouter.OptionStrategy _type) private view returns (uint256) {
        uint256 totalAssets_ = vaultBalance[IRouter.OptionStrategy.BULL] + vaultBalance[IRouter.OptionStrategy.BEAR]
            + vaultBalance[IRouter.OptionStrategy.CRAB];

        // Avoid underflow risk
        if (totalAssets_ < amount * vaultBalance[_type]) {
            return amount.mulDivDown(vaultBalance[_type], totalAssets_);
        }

        return 0;
    }

    /**
     * @notice Claim and stake farm rewards and update internal accounting.
     */
    function _autoCompound() private {
        // Claim and stake in farm
        uint256 earned = farm.claimAndStake(router);

        if (earned > 0) {
            uint256 bullAssets = vaultBalance[IRouter.OptionStrategy.BULL];
            uint256 bearAssets = vaultBalance[IRouter.OptionStrategy.BEAR];
            uint256 crabAssets = vaultBalance[IRouter.OptionStrategy.CRAB];

            uint256 totalBalance = bullAssets + bearAssets + crabAssets;

            uint256 bullEarned = earned.mulDivDown(bullAssets, totalBalance);
            uint256 bearEarned = earned.mulDivDown(bearAssets, totalBalance);
            uint256 crabEarned = earned - bullEarned - bearEarned;

            vaultBalance[IRouter.OptionStrategy.BULL] = vaultBalance[IRouter.OptionStrategy.BULL] + bullEarned;
            vaultBalance[IRouter.OptionStrategy.BEAR] = vaultBalance[IRouter.OptionStrategy.BEAR] + bearEarned;
            vaultBalance[IRouter.OptionStrategy.CRAB] = vaultBalance[IRouter.OptionStrategy.CRAB] + crabEarned;

            emit AutoCompound(earned, bullEarned, bearEarned, crabEarned, block.timestamp);
        }
    }

    /**
     * @notice Process flip from one vault to other.
     */
    function _flip(GeneralInfo memory generalInfo) private returns (FlipInfo memory flipInfo) {
        // Get flip signals
        flipInfo.bullToBear = generalInfo.router.flipSignals(generalInfo.bullStrat, generalInfo.bearStrat);
        flipInfo.bullToCrab = generalInfo.router.flipSignals(generalInfo.bullStrat, generalInfo.crabStrat);
        flipInfo.bearToBull = generalInfo.router.flipSignals(generalInfo.bearStrat, generalInfo.bullStrat);
        flipInfo.bearToCrab = generalInfo.router.flipSignals(generalInfo.bearStrat, generalInfo.crabStrat);
        flipInfo.crabToBull = generalInfo.router.flipSignals(generalInfo.crabStrat, generalInfo.bullStrat);
        flipInfo.crabToBear = generalInfo.router.flipSignals(generalInfo.crabStrat, generalInfo.bearStrat);

        // Calculate shares per signal
        flipInfo.redeemBullToBearAssets = generalInfo.bullVault.previewRedeem(flipInfo.bullToBear);
        flipInfo.redeemBullToCrabAssets = generalInfo.bullVault.previewRedeem(flipInfo.bullToCrab);
        flipInfo.redeemBearToBullAssets = generalInfo.bearVault.previewRedeem(flipInfo.bearToBull);
        flipInfo.redeemBearToCrabAssets = generalInfo.bearVault.previewRedeem(flipInfo.bearToCrab);
        flipInfo.redeemCrabToBullAssets = generalInfo.crabVault.previewRedeem(flipInfo.crabToBull);
        flipInfo.redeemCrabToBearAssets = generalInfo.crabVault.previewRedeem(flipInfo.crabToBear);

        // Remove all shares & balances
        generalInfo.bullVault.burn(generalInfo.routerAddress, flipInfo.bullToBear + flipInfo.bullToCrab);
        vaultBalance[generalInfo.bullStrat] =
            vaultBalance[generalInfo.bullStrat] - flipInfo.redeemBullToBearAssets - flipInfo.redeemBullToCrabAssets;

        generalInfo.bearVault.burn(generalInfo.routerAddress, flipInfo.bearToBull + flipInfo.bearToCrab);
        vaultBalance[generalInfo.bearStrat] =
            vaultBalance[generalInfo.bearStrat] - flipInfo.redeemBearToBullAssets - flipInfo.redeemBearToCrabAssets;

        generalInfo.crabVault.burn(generalInfo.routerAddress, flipInfo.crabToBull + flipInfo.crabToBear);
        vaultBalance[generalInfo.crabStrat] =
            vaultBalance[generalInfo.crabStrat] - flipInfo.redeemCrabToBullAssets - flipInfo.redeemCrabToBearAssets;

        // Add shares & balances
        flipInfo.bullToBearShares = generalInfo.bearVault.previewDeposit(flipInfo.redeemBullToBearAssets);
        flipInfo.bullToCrabShares = generalInfo.crabVault.previewDeposit(flipInfo.redeemBullToCrabAssets);
        flipInfo.bearToBullShares = generalInfo.bullVault.previewDeposit(flipInfo.redeemBearToBullAssets);
        flipInfo.bearToCrabShares = generalInfo.crabVault.previewDeposit(flipInfo.redeemBearToCrabAssets);
        flipInfo.crabToBearShares = generalInfo.bearVault.previewDeposit(flipInfo.redeemCrabToBearAssets);
        flipInfo.crabToBullShares = generalInfo.bullVault.previewDeposit(flipInfo.redeemCrabToBullAssets);

        generalInfo.bullVault.mint(flipInfo.bearToBullShares + flipInfo.crabToBullShares, generalInfo.routerAddress);
        vaultBalance[generalInfo.bullStrat] =
            vaultBalance[generalInfo.bullStrat] + flipInfo.redeemBearToBullAssets + flipInfo.redeemCrabToBullAssets;

        generalInfo.bearVault.mint(flipInfo.bullToBearShares + flipInfo.crabToBearShares, generalInfo.routerAddress);
        vaultBalance[generalInfo.bearStrat] =
            vaultBalance[generalInfo.bearStrat] + flipInfo.redeemBullToBearAssets + flipInfo.redeemCrabToBearAssets;

        generalInfo.crabVault.mint(flipInfo.bullToCrabShares + flipInfo.bearToCrabShares, generalInfo.routerAddress);
        vaultBalance[generalInfo.crabStrat] =
            vaultBalance[generalInfo.crabStrat] + flipInfo.redeemBullToCrabAssets + flipInfo.redeemBearToCrabAssets;
    }

    /**
     * @notice Process withdraw signals.
     */
    function _withdraw(GeneralInfo memory generalInfo) private returns (WithdrawInfo memory withdrawInfo) {
        // Get withdraw signals
        withdrawInfo.bullShares = generalInfo.router.withdrawSignals(generalInfo.bullStrat);
        withdrawInfo.bearShares = generalInfo.router.withdrawSignals(generalInfo.bearStrat);

        // Calculate assets per signal & total
        withdrawInfo.bullAssets = generalInfo.bullVault.previewRedeem(withdrawInfo.bullShares);
        withdrawInfo.bearAssets = generalInfo.bearVault.previewRedeem(withdrawInfo.bearShares);
        withdrawInfo.totalSignals = withdrawInfo.bullAssets + withdrawInfo.bearAssets;

        // Calculate incentive retention
        (address incentiveReceiver, uint256 withdrawRetention,) = generalInfo.router.incentives();
        withdrawInfo.bullRetention = withdrawInfo.bullAssets.mulDivDown(withdrawRetention, BASIS);
        withdrawInfo.bearRetention = withdrawInfo.bearAssets.mulDivDown(withdrawRetention, BASIS);
        withdrawInfo.retention = withdrawInfo.bullRetention + withdrawInfo.bearRetention;

        withdrawInfo.toTreasury = withdrawInfo.retention.mulDivDown(2, 3);

        withdrawInfo.toPayBack = withdrawInfo.totalSignals - withdrawInfo.retention;

        withdrawInfo.currentBalance = lpToken.balanceOf(generalInfo.thisAddress);

        if (withdrawInfo.currentBalance < withdrawInfo.toPayBack + withdrawInfo.toTreasury) {
            farm.unstake(
                withdrawInfo.toPayBack + withdrawInfo.toTreasury - withdrawInfo.currentBalance, generalInfo.thisAddress
            );
        }

        // payback, send incentives & burn shares
        generalInfo.lpToken.transfer(generalInfo.routerAddress, withdrawInfo.toPayBack);
        generalInfo.lpToken.transfer(incentiveReceiver, withdrawInfo.toTreasury);

        generalInfo.bullVault.burn(generalInfo.routerAddress, withdrawInfo.bullShares);
        generalInfo.bearVault.burn(generalInfo.routerAddress, withdrawInfo.bearShares);

        // Update vault balances
        vaultBalance[generalInfo.bullStrat] = vaultBalance[generalInfo.bullStrat] - withdrawInfo.bullAssets;
        vaultBalance[generalInfo.bearStrat] = vaultBalance[generalInfo.bearStrat] - withdrawInfo.bearAssets;
    }

    /**
     * @notice Process next epoch deposits.
     */
    function _deposit(GeneralInfo memory generalInfo) private returns (DepositInfo memory depositInfo) {
        // Get next epoch deposit
        depositInfo.depositBullAssets = generalInfo.router.nextEpochDeposits(generalInfo.bullStrat);
        depositInfo.depositBearAssets = generalInfo.router.nextEpochDeposits(generalInfo.bearStrat);

        // Get calculate their shares
        depositInfo.depositBullShares = generalInfo.bullVault.previewDeposit(depositInfo.depositBullAssets);
        depositInfo.depositBearShares = generalInfo.bearVault.previewDeposit(depositInfo.depositBearAssets);

        // Mint their shares
        generalInfo.bullVault.mint(depositInfo.depositBullShares, generalInfo.routerAddress);
        generalInfo.bearVault.mint(depositInfo.depositBearShares, generalInfo.routerAddress);

        // Calculate rates in order to claim the shares later
        depositInfo.depositBullRate = depositInfo.depositBullAssets > 0
            ? depositInfo.depositBullShares.mulDivDown(1e30, depositInfo.depositBullAssets)
            : 0;

        depositInfo.depositBearRate = depositInfo.depositBearAssets > 0
            ? depositInfo.depositBearShares.mulDivDown(1e30, depositInfo.depositBearAssets)
            : 0;

        // Update vault balances
        vaultBalance[generalInfo.bullStrat] = vaultBalance[generalInfo.bullStrat] + depositInfo.depositBullAssets;
        vaultBalance[generalInfo.bearStrat] = vaultBalance[generalInfo.bearStrat] + depositInfo.depositBearAssets;
    }

    /* -------------------------------------------------------------------------- */
    /*                                   EVENTS                                   */
    /* -------------------------------------------------------------------------- */

    event StartEpoch(
        uint16 epoch,
        uint64 startTime,
        uint256 virtualEndTime,
        uint256 optionsAmount,
        uint256 bullDeposits,
        uint256 bearDeposits,
        uint256 crabDeposits
    );
    event EndEpoch(uint16 epoch, uint256 endTime, uint256 withdrawSignals, uint256 retention);
    event AutoCompound(uint256 earned, uint256 bullEarned, uint256 bearEarned, uint256 crabEarned, uint256 timestamp);
    event EmergencyWithdrawal(address indexed caller, address indexed receiver, IERC20 indexed token, uint256 amount);

    /* -------------------------------------------------------------------------- */
    /*                                    ERRORS                                  */
    /* -------------------------------------------------------------------------- */

    error OutOfRange();
    error EpochOngoing();
    error InsufficientFunds();
}

