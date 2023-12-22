// SPDX-License-Identifier: UNLICENSED

// Copyright (c) 2023 JonesDAO - All rights reserved
// Jones DAO: https://www.jonesdao.io/

// Check https://docs.jonesdao.io/jones-dao/other/bounty for details on our bounty program.

pragma solidity ^0.8.10;

import {ICompoundStrategy} from "./CompoundStrategy.sol";
import {IOptionStrategy} from "./OptionStrategy.sol";
import {ILPVault} from "./ILPVault.sol";
import {IRouter} from "./IRouter.sol";

interface IViewer {
    struct Addresses {
        ICompoundStrategy compoundStrategy;
        IOptionStrategy optionStrategy;
        IRouter router;
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
    ) external view returns (IRouter.FlipSignal memory);

    /**
     * @param _strategy Bull/Bear/Crab
     * @param _targetEpoch Epoch the user will get his withdrawal
     * @param _user Owner of the assets
     * @return Struct with the user's signal information
     */
    function getWithdrawalSignal(IRouter.OptionStrategy _strategy, uint256 _targetEpoch, address _user, address lp)
        external
        view
        returns (IRouter.WithdrawalSignal memory);

    /**
     * @notice Get the vaults addresses
     * @param _strategy Bull/Bear/Crab
     * @return return the corresponding vault to given strategy type
     */
    function vaultAddresses(IRouter.OptionStrategy _strategy, address lp) external view returns (ILPVault);

    /**
     * @return Return the current Compound Strategy's epoch
     */
    function getEpochData(uint256 _epoch, address lp) external view returns (ICompoundStrategy.Epoch memory);

    /**
     * @return Returns the number of the current epoch
     */
    function currentEpoch(address lp) external view returns (uint256);

    /**
     * @param _strategy Bull/Bear/Crab
     * @return Amount of assets of the given vault
     */
    function totalAssets(IRouter.OptionStrategy _strategy, address lp) external view returns (uint256);

    /**
     * @param _strategy Bull/Bear/Crab
     * @param _user User that owns the shares
     * @return Amount of shares for given user
     */
    function balanceOf(IRouter.OptionStrategy _strategy, address _user, address lp) external view returns (uint256);

    /**
     * @param _strategy Bull/Bear/Crab
     * @param _amount Amount of shares
     * @return Amount of assets that will be received
     * @return Amount of incentive retention
     */
    function previewRedeem(IRouter.OptionStrategy _strategy, uint256 _amount, address lp)
        external
        view
        returns (uint256, uint256);

    /**
     * @param _strategy Bull/Bear/Crab
     * @param _amount Amount of assets
     * @return Amount of shares that will be received
     */
    function previewDeposit(IRouter.OptionStrategy _strategy, uint256 _amount, address lp)
        external
        view
        returns (uint256);

    /**
     * @param lp Address of the underlying LP token of given metavault.
     * @return addresses of the desired metavault
     */
    function getMetavault(address lp) external view returns (Addresses memory);

    /**
     * @param _newAddresses update Metavaults V2 contracts
     */
    function setAddresses(address lp, Addresses memory _newAddresses) external;
}

