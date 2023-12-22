/**
 * A Global LP Adapter,
 * enables onchain storage classification of clients
 */

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;
import "./ClientsManager.sol";

contract LpAdapterFacet is LpClientsManagerFacet {
    /**
     * Add Liquidity To A Protocol
     */
    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountA,
        uint256 amountB,
        bytes32 clientId,
        bytes[] memory extraArgs
    ) external {
        LpAdapterStorage storage lpStorage = LpAdapterStorageLib
            .getLpAdapterStorage();

        LPClient memory client = lpStorage.clientsSelectors[clientId];
        bytes4 clientSel = lpStorage.clientsSelectors[clientId].addSelector;

        require(clientSel != bytes4(0), "Lp LPClient Non Existant");

        (bool success, ) = address(this).delegatecall(
            abi.encodeWithSelector(
                clientSel,
                client,
                tokenA,
                tokenB,
                amountA,
                amountB,
                client.extraData,
                extraArgs
            )
        );

        require(success, "Adding Lp Failed");
    }

    /**
     * Remove Liquidity From A Protocol
     */
    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint256 lpAmount,
        bytes32 clientId,
        bytes[] memory extraArgs
    ) external {
        LpAdapterStorage storage lpStorage = LpAdapterStorageLib
            .getLpAdapterStorage();

        LPClient memory client = lpStorage.clientsSelectors[clientId];
        bytes4 clientSel = lpStorage.clientsSelectors[clientId].removeSelector;

        require(clientSel != bytes4(0), "Lp LPClient Non Existant");

        (bool success, ) = address(this).delegatecall(
            abi.encodeWithSelector(
                clientSel,
                client,
                tokenA,
                tokenB,
                lpAmount,
                client.extraData,
                extraArgs
            )
        );

        require(success, "Removing Lp Failed");
    }

    /**
     * Harvest Rewards From A Protocol
     */
    function harvestLiquidityRewards(
        address tokenA,
        address tokenB,
        bytes32 clientId,
        bytes[] memory extraArgs
    ) external {
        LpAdapterStorage storage lpStorage = LpAdapterStorageLib
            .getLpAdapterStorage();

        LPClient memory client = lpStorage.clientsSelectors[clientId];
        bytes4 clientSel = lpStorage.clientsSelectors[clientId].harvestSelector;

        require(
            clientSel != bytes4(0),
            "Lp LPClient Non Existant, Or Harvest Unavailable"
        );

        (bool success, ) = address(this).delegatecall(
            abi.encodeWithSelector(
                clientSel,
                client,
                tokenA,
                tokenB,
                client.extraData,
                extraArgs
            )
        );

        require(success, "Harvesting Lp Failed");
    }
}

