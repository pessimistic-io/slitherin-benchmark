// SPDX-License-Identifier: MIT

pragma solidity 0.8.6;
import "./IVault.sol";


/**
 * @title The WeightedPool v4 create and join helper
 * @author tritium.eth
 * @notice This contract attempts to make creating and initjoining a pool easier from etherscan
 */
contract WeightedPoolInitHelper {
    IVault public immutable vault;

    constructor(IVault _vault) {
        vault = _vault;
    }

    /**
     * @notice Init Joins an empty pool to set the starting price
     * @param poolId the pool id of the pool to init join
     * @param tokenAddresses a list of all the tokens in the pool
     * @param amountsPerToken a list of amounts such that a matching index returns a token/amount pair
     */
    function initJoinWeightedPool(
        bytes32 poolId,
        address[] memory tokenAddresses,
        uint256[] memory amountsPerToken
    ) public {
        require(tokenAddresses.length == amountsPerToken.length, "Arrays of different length");
        IAsset[] memory tokens = toIAssetArray(tokenAddresses);

        // The 0 as the first argument represents an init join
        bytes memory userData = abi.encode(0, amountsPerToken);

        // Construct the JoinPoolRequest struct
        IVault.JoinPoolRequest memory request = IVault.JoinPoolRequest({
            assets: tokens,
            maxAmountsIn: amountsPerToken,
            userData: userData,
            fromInternalBalance: false
        });

        // Call the joinPool function
        for (uint8 i=0; i < tokenAddresses.length; i++) {
            IERC20 t = IERC20(tokenAddresses[i]);
            t.transferFrom(msg.sender, address(this), amountsPerToken[i]);
            t.approve(address(vault), amountsPerToken[i]);
        }
        vault.joinPool(poolId, address(this), msg.sender, request);
    }


    /**
     * @notice Converts an array of token addresses to an array of IAsset objects
     * @param tokenAddresses the array of token addresses to convert
     * @return the array of IAsset objects
     */
    function toIAssetArray(address[] memory tokenAddresses) private pure returns (IAsset[] memory) {
        IAsset[] memory assets = new IAsset[](tokenAddresses.length);
        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            assets[i] = IAsset(tokenAddresses[i]);
        }
        return assets;
    }

    function sortAddressesByAmounts(address[] memory addresses, uint256[] memory amounts) public returns (address[] memory, uint256[] memory) {
    uint256 n = addresses.length;
    for (uint256 i = 0; i < n - 1; i++) {
        for (uint256 j = 0; j < n - i - 1; j++) {
            if (addresses[j] > addresses[j + 1]) {
                address tempAddress = addresses[j];
                addresses[j] = addresses[j + 1];
                addresses[j + 1] = tempAddress;
                uint256 tempAmount = amounts[j];
                amounts[j] = amounts[j + 1];
                amounts[j + 1] = tempAmount;
            }
        }
    }
    return (addresses, amounts);
    }

}





