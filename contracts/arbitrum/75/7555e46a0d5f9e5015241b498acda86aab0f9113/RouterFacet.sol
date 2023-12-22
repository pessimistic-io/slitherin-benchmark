// SPDX-License-Identifier: UNLICENSED

// Copyright (c) 2023 JonesDAO - All rights reserved
// Jones DAO: https://www.jonesdao.io/

// Check https://docs.jonesdao.io/jones-dao/other/bounty for details on our bounty program.

pragma solidity ^0.8.10;

import {IERC20} from "./IERC20.sol";

import {IRouter} from "./IRouter.sol";
import {ILPVault} from "./ILPVault.sol";
import {ICompoundStrategy} from "./ICompoundStrategy.sol";
import {IOptionStrategy} from "./IOptionStrategy.sol";

import {LibDiamond} from "./LibDiamond.sol";
import {RouterLib} from "./RouterLib.sol";
import {FlipLib} from "./FlipLib.sol";
import {WithdrawLib} from "./WithdrawLib.sol";
import {DepositLib} from "./DepositLib.sol";

contract RouterFacet {
    /* -------------------------------------------------------------------------- */
    /*                                    INIT                                    */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice Initialize the router.
     */
    function initializeRouter(
        address _compoundStrategy,
        address _optionStrategy,
        address[] calldata _strategyVaults,
        uint256 _premium
    ) external {
        LibDiamond.enforceIsContractOwner();
        RouterLib.RouterStorage storage rs = RouterLib.routerStorage();

        if (rs.initialized) {
            revert AlreadyInitialized();
        }

        rs.vaults[IRouter.OptionStrategy.BULL] = ILPVault(_strategyVaults[0]);
        rs.vaults[IRouter.OptionStrategy.BEAR] = ILPVault(_strategyVaults[1]);
        rs.vaults[IRouter.OptionStrategy.CRAB] = ILPVault(_strategyVaults[2]);

        rs.compoundStrategy = ICompoundStrategy(_compoundStrategy);
        rs.optionStrategy = IOptionStrategy(_optionStrategy);

        rs.lpToken = ICompoundStrategy(_compoundStrategy).lpToken();
        rs.premium = _premium;

        rs.basis = 1e12;
        rs.slippage = (999 * 1e12) / 1000;

        rs.initialized = true;
    }

    /* -------------------------------------------------------------------------- */
    /*                                    VIEW                                    */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice Get LP Token.
     */
    function lpToken() external view returns (IERC20) {
        return RouterLib.lpToken();
    }

    /**
     * @notice Get premium.
     */
    function premium() external view returns (uint256) {
        return RouterLib.premium();
    }

    /**
     * @notice Get slippage.
     */
    function slippage() external view returns (uint256) {
        return RouterLib.slippage();
    }

    /**
     * @notice Get strategy vault.
     */
    function vaults(IRouter.OptionStrategy _strategy) external view returns (ILPVault) {
        return RouterLib.vaults(_strategy);
    }

    /**
     * @notice Update Compound Strategy.
     */
    function updateCompoundStrategy(address _compoundStrategy) external {
        LibDiamond.enforceIsContractOwner();
        RouterLib.RouterStorage storage rs = RouterLib.routerStorage();
        rs.compoundStrategy = ICompoundStrategy(_compoundStrategy);
        rs.lpToken = ICompoundStrategy(_compoundStrategy).lpToken();
    }

    /**
     * @notice Update Option Strategy.
     */
    function updateOptionStrategy(address _optionStrategy) external {
        LibDiamond.enforceIsContractOwner();
        RouterLib.RouterStorage storage rs = RouterLib.routerStorage();
        rs.optionStrategy = IOptionStrategy(_optionStrategy);
    }

    /**
     * @notice Update Premium.
     */
    function updatePremium(uint256 _premium) external {
        LibDiamond.enforceIsContractOwner();
        RouterLib.RouterStorage storage rs = RouterLib.routerStorage();
        rs.premium = _premium;
    }

    /**
     * @notice Updates slippage.
     */
    function updateSlippage(uint256 _slippage) external {
        LibDiamond.enforceIsContractOwner();
        RouterLib.RouterStorage storage rs = RouterLib.routerStorage();
        rs.slippage = _slippage;
    }

    /**
     * @notice Moves assets from the strategy to `_to`
     * @param _assets An array of IERC20 compatible tokens to move out from the strategy
     * @param _withdrawNative `true` if we want to move the native asset from the strategy
     */
    function emergencyWithdraw(address _to, address[] memory _assets, bool _withdrawNative) external {
        LibDiamond.enforceIsContractOwner();
        uint256 assetsLength = _assets.length;
        for (uint256 i = 0; i < assetsLength; i++) {
            IERC20 asset = IERC20(_assets[i]);
            uint256 assetBalance = asset.balanceOf(address(this));

            if (assetBalance > 0) {
                // Transfer the ERC20 tokens
                asset.transfer(_to, assetBalance);
            }

            unchecked {
                ++i;
            }
        }

        uint256 nativeBalance = address(this).balance;

        // Nothing else to do
        if (_withdrawNative && nativeBalance > 0) {
            // Transfer the native currency
            (bool sent,) = payable(_to).call{value: nativeBalance}("");
            if (!sent) {
                revert FailSendETH();
            }
        }

        emit EmergencyWithdrawal(msg.sender, _to, _assets, _withdrawNative ? nativeBalance : 0);
    }

    /* -------------------------------------------------------------------------- */
    /*                                 ONLY STRATEGY                              */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice Update accounting when epoch finish.
     */
    function executeFinishEpoch() external {
        if (msg.sender != address(RouterLib.compoundStrategy())) revert InvalidStrategy();

        IRouter.OptionStrategy bullStrategy = IRouter.OptionStrategy.BULL;
        IRouter.OptionStrategy bearStrategy = IRouter.OptionStrategy.BEAR;
        IRouter.OptionStrategy crabStrategy = IRouter.OptionStrategy.CRAB;

        FlipLib.FlipStorage storage fs = FlipLib.flipStorage();

        fs.flipSignals[bullStrategy][bearStrategy] = 0;
        fs.flipSignals[bullStrategy][crabStrategy] = 0;
        fs.flipSignals[bearStrategy][bullStrategy] = 0;
        fs.flipSignals[bearStrategy][crabStrategy] = 0;
        fs.flipSignals[crabStrategy][bullStrategy] = 0;
        fs.flipSignals[crabStrategy][bearStrategy] = 0;

        WithdrawLib.WithdrawStorage storage ws = WithdrawLib.withdrawStorage();

        ws.withdrawSignals[bullStrategy] = 0;
        ws.withdrawSignals[bearStrategy] = 0;
        ws.withdrawSignals[crabStrategy] = 0;

        DepositLib.DepositStorage storage ds = DepositLib.depositStorage();

        ds.nextEpochDeposits[bullStrategy] = 0;
        ds.nextEpochDeposits[bearStrategy] = 0;
        ds.nextEpochDeposits[crabStrategy] = 0;
    }

    /* -------------------------------------------------------------------------- */
    /*                                   EVENTS                                   */
    /* -------------------------------------------------------------------------- */

    event EmergencyWithdrawal(address indexed caller, address indexed receiver, address[] tokens, uint256 nativeBalanc);

    /* -------------------------------------------------------------------------- */
    /*                                    ERRORS                                  */
    /* -------------------------------------------------------------------------- */

    error AlreadyInitialized();
    error FailSendETH();
    error InvalidStrategy();
}

