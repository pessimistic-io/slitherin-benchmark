// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.10;

import {VaultBase} from "./VaultBase.sol";
import {IConnectorRouter} from "./IConnectorRouter.sol";
import {IExchangeSwapWithInQuote} from "./IExchangeSwapWithInQuote.sol";
import {IExchangeSwapWithOutQuote} from "./IExchangeSwapWithOutQuote.sol";
import {IERC20Extended} from "./IERC20Extended.sol";
import {ISVS} from "./ISVS.sol";
import {VaultDataTypes} from "./VaultDataTypes.sol";

library Vault1155logic {

    event SvsMinted(address indexed user, uint256 indexed tokenTranche, uint256 indexed numTokens, uint256 stableAmount);
    event SvsRedeemed(address indexed user, uint256 indexed tokenTranche, uint256 indexed numTokens);
    event InitiateReweight(address[] VITs, uint256[] newWeights);

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
        uint256 scaleFactor = 10**decimals;

        for (uint8 i = 0; i < VITs.length; i++) {
            address swapContract = connectorRouter.getSwapContract(VITs[i]);
            quote = IExchangeSwapWithOutQuote(swapContract).getQuoteOut(
                stable,
                VITs[i],
                VITAmounts[i] * _numShares
            );
            quotes[i] = quote * (scaleFactor + depositFee) / scaleFactor;
        }
        return quotes;
    }

    function getTotalQuoteWithVIT(
        IConnectorRouter connectorRouter,
        address stable, 
        address[] calldata VITs, 
        uint256[] calldata VITAmounts, 
        address VITAddress, 
        uint256 _numShares
    ) external returns (uint256[] memory) {
        uint256[] memory quotes = new uint256[](VITs.length-1);
        uint256 quote;
        for (uint8 i = 0; i < VITs.length; i++) {
            if (VITs[i] == VITAddress) {
                continue;
            }
            address swapContract = connectorRouter.getSwapContract(VITs[i]);   
            quote = IExchangeSwapWithOutQuote(swapContract).getQuoteOut(
                stable,
                VITs[i],
                VITAmounts[i] * _numShares
            );
            quotes[i] = quote;
        }
        return quotes;
    }

    function getTotalUnderlying(address[] memory VITs) external view returns (uint256[] memory totalUnderlying) {
        totalUnderlying = new uint256[](VITs.length);
        for (uint8 i = 0; i < VITs.length; i++) {
            totalUnderlying[i] = IERC20Extended(VITs[i]).balanceOf(address(this));
        }
    }

    function getTotalUnderlyingByTranche(
        address[] memory VITs,
        uint256[] memory VITAmounts,
        address svsToken, 
        uint256 tranche
    ) external view returns (uint256[] memory) {
        uint256[] memory totalUnderlying = new uint256[](VITs.length);  
        for (uint8 i = 0; i < VITs.length; i++) {
            uint256 totalSupply = ISVS(svsToken).totalSupplyPerTranche(tranche);
            totalUnderlying[i] = totalSupply * VITAmounts[i];
        }
        return totalUnderlying;
    }

    function mintVaultToken(address admin, VaultDataTypes.MintParams memory params) external {
        
        uint256 fee = 0;
        uint256 stableBalance = IERC20Extended(params.stable).balanceOf(params.vaultAddress);

        IERC20Extended(params.stable).transferFrom(msg.sender, params.vaultAddress, params.stableAmount);
        
        for (uint8 i = 0; i < params.VITs.length; i++) {
            fee += (params.amountPerSwap[i] * params.depositFee) / 10000;
            exchangeSwap(params, i);
        }

        ISVS(params.svs).mint(msg.sender, params.currentTranche + uint8(params.lockup), params.numShares, "");
        uint256 newStableBalance = IERC20Extended(params.stable).balanceOf(params.vaultAddress);
        require(newStableBalance >= stableBalance + fee, "Not enough stableAmount to pay depositFee"); //<--- this breaks it ???? wtf?
        IERC20Extended(params.stable).transfer(msg.sender, newStableBalance - stableBalance - fee);
        IERC20Extended(params.stable).transfer(admin, fee);
        emit SvsMinted(msg.sender, params.currentTranche, params.numShares, params.stableAmount);

    }

    function mintVaultTokenWithVIT(address admin, VaultDataTypes.MintParams memory params, address mintVITAddress, uint256 mintVITAmount) external {
        uint256 fee = (params.depositFee * params.stableAmount) / 10000;
        
        uint256 stableBalance = IERC20Extended(params.stable).balanceOf(address(this));
        IERC20Extended(params.stable).transferFrom(msg.sender, address(this), params.stableAmount);
        IERC20Extended(mintVITAddress).transferFrom(msg.sender, address(this), mintVITAmount);
        for (uint8 i = 0; i < params.VITs.length; i++) {
            exchangeSwap(params, i);
        }     
        ISVS(params.svs).mint(msg.sender, params.currentTranche + uint8(params.lockup), params.numShares, "");   
        uint256 newStableBalance = IERC20Extended(params.stable).balanceOf(address(this));

        require(newStableBalance - stableBalance >= fee, "Not enough stableAmount to pay depositFee");
        IERC20Extended(params.stable).transfer(msg.sender, newStableBalance - stableBalance - fee);
        IERC20Extended(params.stable).transfer(admin, fee);
        
        emit SvsMinted(msg.sender, params.currentTranche, params.numShares, params.stableAmount);
    }

    function exchangeSwap(VaultDataTypes.MintParams memory params, uint8 i) internal {
        address exchangeSwapContract = IConnectorRouter(params.swapRouter).getSwapContract(params.VITs[i]);
        uint256 computedAmount = params.VITAmounts[i] * params.numShares;            
        IExchangeSwapWithOutQuote(exchangeSwapContract).swap(params.stable, params.VITs[i], params.amountPerSwap[i], computedAmount);
    }

    function redeemUnderlying(
        address admin,
        address sender,
        address svsToken,
        uint256 _numShares,
        uint256 _tranche,
        uint256 lockupEnd,
        address[] memory VITs,
        uint256[] memory VITAmounts,
        uint256 redemptionFee,
        uint256 currentTranche 
    ) external {
        require(block.timestamp > lockupEnd, "Vesting not ended");
        ISVS(svsToken).burn(sender, _tranche, _numShares);

        for(uint8 i = 0; i < VITs.length; i++) {
            uint256 totalAmount = VITAmounts[i] * _numShares;
            uint256 fee = (totalAmount * redemptionFee) / 10000; // Calculate fee in basis points (0.1% when data.fee.redemptionFee is 10)
            uint256 userAmount = totalAmount - fee;
            IERC20Extended(VITs[i]).transfer(sender, userAmount);
            IERC20Extended(VITs[i]).transfer(admin, fee);
        }

        emit SvsRedeemed(sender, currentTranche, _numShares);
    }    

    function initiateReweight(
        address sender, 
        address reweighter, 
        address[] memory _VITs, 
        uint256[] memory _amounts
    ) external {
        require(sender == reweighter, "Only reweighter");

        for(uint8 i = 0; i < _VITs.length; i++) {
            IERC20Extended(_VITs[i]).transferFrom(sender, address(this), _amounts[i]);
        }

        emit InitiateReweight(_VITs, _amounts);
    }
}
