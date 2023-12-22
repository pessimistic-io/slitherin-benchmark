// SPDX-License-Identifier: UNLICENSED

// Copyright (c) 2023 JonesDAO - All rights reserved
// Jones DAO: https://www.jonesdao.io/

// Check https://docs.jonesdao.io/jones-dao/other/bounty for details on our bounty program.

pragma solidity ^0.8.10;

import {FixedPointMathLib} from "./FixedPointMathLib.sol";
import {UpgradeableGovernable} from "./UpgradeableGovernable.sol";
import {ICompoundStrategy} from "./CompoundStrategy.sol";
import {IOptionStrategy} from "./IOptionStrategy.sol";
import {ILPVault} from "./ILPVault.sol";
import {IOption} from "./IOption.sol";
import {IViewer} from "./IViewer.sol";
import {IRouter} from "./IRouter.sol";

contract Viewer is IViewer, UpgradeableGovernable {
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

    // LP address of metavault -> struct containing its contracts.
    mapping(address => Addresses) public metavault;

    function initiaze(address[] calldata lpAddresses, Addresses[] calldata addresses) public initializer {
        __Governable_init(msg.sender);

        uint256 length = lpAddresses.length;

        if (length != addresses.length) {
            revert LengthMismatch();
        }

        for (uint256 i; i < length;) {
            if (lpAddresses[i] == address(0)) {
                revert ZeroAddress();
            }

            metavault[lpAddresses[i]] = addresses[i];

            unchecked {
                ++i;
            }
        }
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

    /* =============== Governor =============== */

    /**
     * @param _newAddresses update Metavaults V2 contracts
     */
    function updateAddresses(address lp, Addresses memory _newAddresses) external onlyGovernor {
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

    error LengthMismatch();
    error ZeroAddress();
}

