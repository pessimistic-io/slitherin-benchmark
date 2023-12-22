// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { Controller } from "./Controller.sol";
import { BaseSwapAdapter } from "./BaseSwapAdapter.sol";
import { FeeMapping } from "./FeeMapping.sol";
import { PriceOracleManager } from "./PriceOracleManager.sol";
import { SwapAdapterRegistry } from "./SwapAdapterRegistry.sol";
import { TauDripFeed } from "./TauDripFeed.sol";

import { SafeERC20 } from "./SafeERC20.sol";
import { ERC20Burnable } from "./ERC20Burnable.sol";
import { IERC20 } from "./IERC20.sol";

// Libraries
import { Constants } from "./Constants.sol";

// Note that any contract attempting to swap must be given the VAULT_ROLE in the Controller.
abstract contract SwapHandler is FeeMapping, TauDripFeed {
    using SafeERC20 for IERC20;

    // Errors
    error notContract();
    error oracleCorrupt();
    error tokenCannotBeSwapped();
    error tooMuchSlippage(uint256 actualTauReturned, uint256 _minTauReturned);
    error unregisteredSwapAdapter();
    error zeroAmount();
    error rewardProportionTooHigh();

    event Swap(address indexed fromToken, uint256 feesToProtocol, uint256 fromAmount, uint256 tauReturned);

    /**
     * @dev function called as part of the yield pull process. This will fetch swap modules from the Controller, use them 
        to handle a swap from vault yield to tau, then validate that the swap did not encounter too much slippage.
     * @param _yieldTokenAddress is the address of the token to be swapped. Must be a yield token, so cannot be the vault's collateral token or tau.
     * @param _yieldTokenAmount is the amount of yield token. Some will be transferred to the FeeSplitter for use by the protocol. The rest will be swapped for tau.
     * note that slippage parameters must be built based on the amount to be swapped, not based on _yieldTokenAmount above (some of which will not be swapped).
     * @param _swapAdapterHash is the hash of the swap adapter to be used, i.e. keccak256("UniswapSwapAdapter") for the UniswapSwapAdapter.
     * @param _rewardProportion refers to the proportion of received tau which will be rewarded (i.e. pay back user loans). The remainder will simply be burned without
     * being distributed to users. This undistributed tau cancels out bad debt in the vault. All vaults retain a growing reserve of yield to ensure bad debt
     * will always be covered.
     * _rewardProportion has a precision of 1e18. If _rewardProportion = 1e18, all tau will be disbursed to users. If _rewardProportion = 0, none of the burned tau will be disbursed.
     * @param _swapParams is the params to be passed to the SwapAdapter.
     * note that this function may only be called by a registered keeper.
     */
    function swapForTau(
        address _yieldTokenAddress,
        uint256 _yieldTokenAmount,
        uint256 _minTauReturned,
        bytes32 _swapAdapterHash,
        uint256 _rewardProportion,
        bytes calldata _swapParams
    ) external onlyKeeper whenNotPaused {
        // Ensure keeper is allowed to swap this token
        if (_yieldTokenAddress == collateralToken) {
            revert tokenCannotBeSwapped();
        }

        if (_yieldTokenAmount == 0) {
            revert zeroAmount();
        }

        if (_rewardProportion > Constants.PERCENT_PRECISION) {
            revert rewardProportionTooHigh();
        }

        if (_minTauReturned == 0) {
            revert zeroAmount();
        }

        // Get and validate swap adapter address
        address swapAdapterAddress = SwapAdapterRegistry(controller).swapAdapters(_swapAdapterHash);
        if (swapAdapterAddress == address(0)) {
            // The given hash has not yet been approved as a swap adapter.
            revert unregisteredSwapAdapter();
        }

        // Calculate portion of tokens which will be swapped for TAU and disbursed to the vault, and portion which will be sent to the protocol.
        uint256 protocolFees = (feeMapping[Constants.VAULT_PROTOCOL_FEE_KEY] * _yieldTokenAmount) /
            Constants.PERCENT_PRECISION;
        uint256 swapAmount = _yieldTokenAmount - protocolFees;

        // Transfer tokens to swap adapter
        IERC20(_yieldTokenAddress).safeTransfer(swapAdapterAddress, swapAmount);

        // Call swap function, which will transfer resulting tau back to this contract and return the amount transferred.
        // Note that this contract does not check that the swap adapter has transferred the correct amount of tau. This check
        // is handled by the swap adapter, and for this reason any registered swap adapter must be a completely trusted contract.
        uint256 tauReturned = BaseSwapAdapter(swapAdapterAddress).swap(tau, _swapParams);

        if (tauReturned < _minTauReturned) {
            revert tooMuchSlippage(tauReturned, _minTauReturned);
        }

        // Burn received Tau
        ERC20Burnable(tau).burn(tauReturned);

        // Add Tau rewards to withheldTAU to avert sandwich attacks
        _disburseTau();
        _withholdTau((tauReturned * _rewardProportion) / Constants.PERCENT_PRECISION);

        // Send protocol fees to FeeSplitter
        IERC20(_yieldTokenAddress).safeTransfer(
            Controller(controller).addressMapper(Constants.FEE_SPLITTER),
            protocolFees
        );

        // Emit event
        emit Swap(_yieldTokenAddress, protocolFees, swapAmount, tauReturned);
    }

    uint256[50] private __gap;
}

