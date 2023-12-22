/**
 *  storage for AAVE V3 adapter
 */
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;
import "./AccessControlled.sol";
import {IPoolAddressesProviderRegistry} from "./IPoolAddressesProviderRegistry.sol";
import "./AaveV3.sol";

contract AaveV3AdapterStorageManager is AccessControlled {
    // ====================
    //       MODIFIERS
    // ====================
    modifier onlyAdapter() {
        require(
            msg.sender ==
                address(AaveV3AdapterStorageLib.retreive().aaveV3Adapter),
            "Not AaveV3 Adapter"
        );
        _;
    }

    // ====================
    //       METHODS
    // ====================

    function increaseVaultPrincipal(IAToken asset, uint256 amt) external {
        AaveV3AdapterStorage storage aaveStorage = AaveV3AdapterStorageLib
            .retreive();

        aaveStorage.principalDeposits[msg.sender][asset] += amt;
    }

    function decreaseVaultPrincipal(IAToken asset, uint256 amt) external {
        AaveV3AdapterStorage storage aaveStorage = AaveV3AdapterStorageLib
            .retreive();

        aaveStorage.principalDeposits[msg.sender][asset] += amt;
    }

    function getVaultPrincipal(
        address vault,
        IAToken asset
    ) external view returns (uint256 principal) {
        AaveV3AdapterStorage storage aaveStorage = AaveV3AdapterStorageLib
            .retreive();

        principal = aaveStorage.principalDeposits[vault][asset];
    }

    function getYcReferralCode() external view returns (uint16 refcode) {
        refcode = AaveV3AdapterStorageLib.retreive().YIELDCHAIN_REFFERAL_CODE;
    }

    // ==================================
    //    CLASSIFICATIONS / READING
    // ==================================

    function setAaveAdapterAddress(
        ILendingProvider adapterAddress
    ) external onlyOwner {
        AaveV3AdapterStorageLib.retreive().aaveV3Adapter = adapterAddress;
    }

    function addAaveV3Client(
        bytes32 clientID,
        IPoolAddressesProviderRegistry clientAddress
    ) external onlyOwner {
        AaveV3AdapterStorage storage aaveStorage = AaveV3AdapterStorageLib
            .retreive();

        require(
            address(aaveStorage.clients[clientID]) == address(0),
            "Client Already Set. Use updateClient"
        );

        aaveStorage.clients[clientID] = clientAddress;
        aaveStorage.clientsIds.push(clientID);
    }

    function removeAaveV3Client(bytes32 clientID) external onlyOwner {
        AaveV3AdapterStorage storage aaveStorage = AaveV3AdapterStorageLib
            .retreive();

        uint256 idx = 123123123123;

        bytes32[] memory clients = aaveStorage.clientsIds;

        for (uint256 i; i < clients.length; i++)
            if (clients[i] == clientID) {
                idx = i;
                break;
            }

        require(idx != 123123123123, "Didnt Find Existing Client");

        aaveStorage.clients[clientID] = IPoolAddressesProviderRegistry(
            address(0)
        );

        aaveStorage.clientsIds[idx] = clients[clients.length - 1];
        aaveStorage.clientsIds.pop();
    }

    function updateAaveV3Client(
        bytes32 clientID,
        IPoolAddressesProviderRegistry clientAddress
    ) external onlyOwner {
        AaveV3AdapterStorage storage aaveStorage = AaveV3AdapterStorageLib
            .retreive();

        require(
            address(aaveStorage.clients[clientID]) != address(0),
            "Client Non Existant. Use addAaveV3Client instead"
        );

        aaveStorage.clients[clientID] = clientAddress;
    }

    function batchAddAaveV3Clients(
        bytes32[] calldata clientsIds,
        IPoolAddressesProviderRegistry[] calldata clients
    ) external onlyOwner {
        require(clientsIds.length == clients.length, "Clients Length Mismatch");

        AaveV3AdapterStorage storage aaveStorage = AaveV3AdapterStorageLib
            .retreive();

        for (uint256 i; i < clients.length; i++) {
            bytes32 clientID = clientsIds[i];
            require(
                address(aaveStorage.clients[clientID]) == address(0),
                "Client Already Added"
            );

            aaveStorage.clients[clientID] = clients[i];
            aaveStorage.clientsIds.push(clientID);
        }
    }

    function getAaveV3Clients()
        external
        view
        returns (IPoolAddressesProviderRegistry[] memory clients)
    {
        AaveV3AdapterStorage storage aaveStorage = AaveV3AdapterStorageLib
            .retreive();
        bytes32[] memory clientsIds = aaveStorage.clientsIds;

        clients = new IPoolAddressesProviderRegistry[](clientsIds.length);
        for (uint256 i; i < clients.length; i++)
            clients[i] = aaveStorage.clients[clientsIds[i]];
    }

    function getAaveV3Client(
        bytes32 clientId
    ) external view returns (IPoolAddressesProviderRegistry client) {
        client = AaveV3AdapterStorageLib.retreive().clients[clientId];
    }
}

