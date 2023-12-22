// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.10;

import {VaultBase} from "./VaultBase.sol";
import {IConnectorRouter} from "./IConnectorRouter.sol";
import {IExchangeSwapWithInQuote} from "./IExchangeSwapWithInQuote.sol";
import {IExchangeSwapWithOutQuote} from "./IExchangeSwapWithOutQuote.sol";
import {IERC20Extended} from "./IERC20Extended.sol";
import {ISVS} from "./ISVS.sol";
import {VaultDataTypes} from "./VaultDataTypes.sol";

/**
 * @title Vault1155logic.sol
 * @author Souq.Finance
 * @notice This library contains logic for handling various operations related to the Vault.
 * @notice License: https://souq-etf.s3.amazonaws.com/LICENSE.md
 */

library Vault1155logic {
    event SvsMinted(address indexed user, uint256 indexed tokenTranche, uint256 indexed numTokens, uint256 stableAmount);
    event SvsRedeemed(address indexed user, uint256 indexed tokenTranche, uint256 indexed numTokens);
    event InitiateReweight(address[] VITs, uint256[] newWeights);

    /**
     * @dev Calculates and returns the total quote for various VITs given the input parameters.
     * @param connectorRouter The connector router contract.
     * @param stable The address of the stable token.
     * @param VITs An array of VIT token addresses.
     * @param VITAmounts An array of corresponding VIT token amounts.
     * @param _numShares The number of shares.
     * @param depositFee The deposit fee.
     * @return An array of total quotes for each VIT.
     */

    function getTotalQuote(
        IConnectorRouter connectorRouter,
        address stable,
        address[] memory VITs,
        uint256[] memory VITAmounts,
        uint256 _numShares,
        uint256 depositFee
    ) public returns (uint256[] memory) {
        uint256[] memory quotes = new uint256[](VITs.length);
        uint256 quote;
        uint8 decimals = IERC20Extended(stable).decimals();
        uint256 scaleFactor = 10 ** decimals;

        for (uint8 i = 0; i < VITs.length; ++i) {
            address swapContract = connectorRouter.getSwapContract(VITs[i]);
            quote = IExchangeSwapWithOutQuote(swapContract).getQuoteOut(stable, VITs[i], VITAmounts[i] * _numShares);
            quotes[i] = (quote * (scaleFactor + depositFee)) / scaleFactor;
        }
        return quotes;
    }

    /**
     * @dev Calculates and returns the total quote for various VITs given the input parameters, excluding a specific VIT.
     * @param connectorRouter The connector router contract.
     * @param stable The address of the stable token.
     * @param VITs An array of VIT token addresses.
     * @param VITAmounts An array of corresponding VIT token amounts.
     * @param VITAddress The address of the VIT to exclude.
     * @param _numShares The number of shares.
     * @return An array of total quotes for each VIT excluding the specified VIT.
     */

    function getTotalQuoteWithVIT(
        IConnectorRouter connectorRouter,
        address stable,
        address[] calldata VITs,
        uint256[] calldata VITAmounts,
        address VITAddress,
        uint256 _numShares
    ) external returns (uint256[] memory) {
        uint256[] memory quotes = new uint256[](VITs.length - 1);
        uint256 quote;
        for (uint8 i = 0; i < VITs.length; ++i) {
            if (VITs[i] == VITAddress) {
                continue;
            }
            address swapContract = connectorRouter.getSwapContract(VITs[i]);
            quote = IExchangeSwapWithOutQuote(swapContract).getQuoteOut(stable, VITs[i], VITAmounts[i] * _numShares);
            quotes[i] = quote;
        }
        return quotes;
    }

    /**
     * @dev Gets the total underlying balance of various VITs.
     * @param VITs An array of VIT token addresses.
     * @return totalUnderlying An array of total underlying balances for each VIT.
     */

    function getTotalUnderlying(address[] memory VITs) external view returns (uint256[] memory totalUnderlying) {
        totalUnderlying = new uint256[](VITs.length);
        for (uint8 i = 0; i < VITs.length; ++i) {
            totalUnderlying[i] = IERC20Extended(VITs[i]).balanceOf(address(this));
        }
    }

    /**
     * @dev Gets the total underlying balance of various VITs by tranche.
     * @param VITs An array of VIT token addresses.
     * @param VITAmounts An array of corresponding VIT token amounts.
     * @param svsToken The address of the SVS token.
     * @param tranche The tranche for which to calculate the total underlying balance.
     * @return An array of total underlying balances for each VIT by tranche.
     */

    function getTotalUnderlyingByTranche(
        address[] memory VITs,
        uint256[] memory VITAmounts,
        address svsToken,
        uint256 tranche
    ) external view returns (uint256[] memory) {
        uint256[] memory totalUnderlying = new uint256[](VITs.length);
        for (uint8 i = 0; i < VITs.length; ++i) {
            uint256 totalSupply = ISVS(svsToken).totalSupplyPerTranche(tranche);
            totalUnderlying[i] = totalSupply * VITAmounts[i];
        }
        return totalUnderlying;
    }

    /**
     * @dev Mints Vault tokens.
     * @param admin The address of the admin.
     * @param params Mint parameters.
     * @return The total amount of tokens minted.
     */

    function mintVaultToken(address admin, VaultDataTypes.MintParams memory params) external returns (uint256) {
        uint256 fee = 0;
        uint256 stableBalance = IERC20Extended(params.stable).balanceOf(params.vaultAddress);

        IERC20Extended(params.stable).transferFrom(msg.sender, params.vaultAddress, params.stableAmount);

        for (uint8 i = 0; i < params.VITs.length; ++i) {
            fee += (params.amountPerSwap[i] * params.depositFee) / 10000;
            exchangeSwap(params, i);
        }

        ISVS(params.svs).mint(msg.sender, params.currentTranche + uint8(params.lockup), params.numShares, "");
        uint256 newStableBalance = IERC20Extended(params.stable).balanceOf(params.vaultAddress);
        require(newStableBalance >= stableBalance + fee, "NOT_ENOUGH_STABLE_AMOUNT");
        uint256 amountReturned = newStableBalance - stableBalance - fee;
        IERC20Extended(params.stable).transfer(msg.sender, amountReturned);
        IERC20Extended(params.stable).transfer(admin, fee);
        emit SvsMinted(msg.sender, params.currentTranche + uint8(params.lockup), params.numShares, params.stableAmount - amountReturned);
        return params.stableAmount + newStableBalance - stableBalance;
    }

    /**
     * @dev Mints Vault tokens with a specified VIT token.
     * @param admin The address of the admin.
     * @param params Mint parameters.
     * @param mintVITAddress The address of the VIT token used for minting.
     * @param mintVITAmount The amount of VIT tokens to be used for minting.
     * @return The total amount of tokens minted.
     */

    function mintVaultTokenWithVIT(
        address admin,
        VaultDataTypes.MintParams memory params,
        address mintVITAddress,
        uint256 mintVITAmount
    ) external returns (uint256) {
        uint256 fee = (params.depositFee * params.stableAmount) / 10000;

        uint256 stableBalance = IERC20Extended(params.stable).balanceOf(address(this));
        IERC20Extended(params.stable).transferFrom(msg.sender, address(this), params.stableAmount);
        IERC20Extended(mintVITAddress).transferFrom(msg.sender, address(this), mintVITAmount);
        for (uint8 i = 0; i < params.VITs.length; ++i) {
            exchangeSwap(params, i);
        }
        ISVS(params.svs).mint(msg.sender, params.currentTranche + uint8(params.lockup), params.numShares, "");
        uint256 newStableBalance = IERC20Extended(params.stable).balanceOf(address(this));
        uint256 amountReturned = newStableBalance - stableBalance - fee;
        require(newStableBalance - stableBalance >= fee, "NOT_ENOUGH_STABLE_AMOUNT");
        IERC20Extended(params.stable).transfer(msg.sender, amountReturned);
        IERC20Extended(params.stable).transfer(admin, fee);

        emit SvsMinted(msg.sender, params.currentTranche + uint8(params.lockup), params.numShares, params.stableAmount - amountReturned);
        return params.stableAmount + newStableBalance - stableBalance;
    }

    function exchangeSwap(VaultDataTypes.MintParams memory params, uint8 i) internal {
        address exchangeSwapContract = IConnectorRouter(params.swapRouter).getSwapContract(params.VITs[i]);

        IERC20Extended(params.stable).approve(exchangeSwapContract, params.amountPerSwap[i]);

        uint256 computedAmount = params.VITAmounts[i] * params.numShares;
        IExchangeSwapWithOutQuote(exchangeSwapContract).swap(params.stable, params.VITs[i], params.amountPerSwap[i], computedAmount);
    }

/**
     * @dev Redeems underlying VIT tokens.
     * @param admin The address of the admin.
     * @param sender The address of the sender.
     * @param svsToken The address of the SVS token.
     * @param _numShares The number of shares.
     * @param _tranche The tranche for which to redeem shares.
     * @param lockupEnd The end of the lockup period.
     * @param VITs An array of VIT token addresses.
     * @param VITAmounts An array of corresponding VIT token amounts.
     * @param redemptionFee The redemption fee.
     */

    function redeemUnderlying(
        address admin,
        address sender,
        address svsToken,
        uint256 _numShares,
        uint256 _tranche,
        uint256 lockupEnd,
        address[] memory VITs,
        uint256[] memory VITAmounts,
        uint256 redemptionFee
    ) external {
        require(block.timestamp > lockupEnd, "VESTING_NOT_ENDED");
        ISVS(svsToken).burn(sender, _tranche, _numShares);

        for (uint8 i = 0; i < VITs.length; ++i) {
            uint256 totalAmount = VITAmounts[i] * _numShares;
            uint256 fee = (totalAmount * redemptionFee) / 10000; // Calculate fee in basis points (0.1% when data.fee.redemptionFee is 10)
            uint256 userAmount = totalAmount - fee;
            IERC20Extended(VITs[i]).transfer(sender, userAmount);
            IERC20Extended(VITs[i]).transfer(admin, fee);
        }

        emit SvsRedeemed(sender, _tranche, _numShares);
    }

    /**
     * @dev Initiates a reweight operation.
     * @param sender The address of the sender.
     * @param reweighter The address of the reweighter.
     * @param _VITs An array of VIT token addresses.
     * @param _amounts An array of corresponding amounts.
     */

    function initiateReweight(address sender, address reweighter, address[] memory _VITs, uint256[] memory _amounts) external {
        require(sender == reweighter, "ONLY_REWEIGHTER");
        require(_VITs.length == _amounts.length, "INPUT_ARRAYS_NOT_SAME_LENGTH");
        for (uint8 i = 0; i < _VITs.length; ++i) {
            IERC20Extended(_VITs[i]).transfer(msg.sender, _amounts[i]);
        }
        emit InitiateReweight(_VITs, _amounts);
    }
}

