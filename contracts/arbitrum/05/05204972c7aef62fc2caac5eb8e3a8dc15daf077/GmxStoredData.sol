// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import { Registry } from "./Registry.sol";
import { VaultBaseExternal } from "./VaultBaseExternal.sol";
import { IntegrationDataTracker, Integration } from "./IntegrationDataTracker.sol";

import { IGmxRouter } from "./IGmxRouter.sol";
import { IGmxPositionRouter } from "./IGmxPositionRouter.sol";
import { IGmxPositionRouterCallbackReceiver } from "./IGmxPositionRouterCallbackReceiver.sol";
import { IGmxVault } from "./IGmxVault.sol";
import { GmxHelpers } from "./GmxHelpers.sol";

library GmxStoredData {
    struct GMXRequestData {
        address _inputToken;
        address _outputToken;
        address _collateralToken;
        address _indexToken;
        bool _isLong;
    }

    struct GMXPositionData {
        address _collateralToken;
        address _indexToken;
        bool _isLong;
    }

    /// @notice Pushes a GmxRequestData to storage
    /// @dev can only be called by the vault
    function pushRequest(
        bytes32 key,
        GMXRequestData memory requestData,
        uint maxRequest
    ) internal {
        Registry registry = VaultBaseExternal(address(this)).registry();
        IntegrationDataTracker dataTracker = registry.integrationDataTracker();
        require(
            address(dataTracker) != address(0),
            'no dataTracker configured'
        );

        require(
            dataTracker.getDataCount(Integration.GMXRequests, address(this)) <
                maxRequest,
            'Gmx: max requests reached'
        );
        dataTracker.pushData(
            Integration.GMXRequests,
            abi.encode(key, requestData)
        );
    }

    /// @notice removes a GmxRequestData in storage by the index
    /// @dev index is returned by findRequest
    function removeRequest(Registry registry, uint index) internal {
        IntegrationDataTracker dataTracker = registry.integrationDataTracker();
        require(
            address(dataTracker) != address(0),
            'no dataTracker configured'
        );

        dataTracker.removeData(Integration.GMXRequests, index);
    }

    /// @notice removes the GMXPositionData at the given index
    ///         for the calling vault if the GMX position is empty
    ///         and there is no outstanding request
    function removePositionIfEmpty(
        GMXPositionData memory keyData,
        uint index
    ) internal {
        if (hasActiveRequest(address(this), keyData)) {
            return;
        }

        Registry registry = VaultBaseExternal(address(this)).registry();
        IntegrationDataTracker dataTracker = registry.integrationDataTracker();
        require(
            address(dataTracker) != address(0),
            'no dataTracker configured'
        );

        (uint256 size, , , , , , , ) = IGmxVault(registry.gmxConfig().vault())
            .getPosition(
                address(this),
                keyData._collateralToken,
                keyData._indexToken,
                keyData._isLong
            );

        if (size == 0) {
            dataTracker.removeData(Integration.GMXPositions, index);
        }
    }

    /// @notice removes the GMXPositionData in storage for the calling vault if the GMX position is empty
    function removePositionIfEmpty(GMXPositionData memory keyData) internal {
        if (hasActiveRequest(address(this), keyData)) {
            return;
        }
        Registry registry = VaultBaseExternal(address(this)).registry();
        IntegrationDataTracker dataTracker = registry.integrationDataTracker();
        require(
            address(dataTracker) != address(0),
            'no dataTracker configured'
        );

        (uint256 size, , , , , , , ) = IGmxVault(registry.gmxConfig().vault())
            .getPosition(
                address(this),
                keyData._collateralToken,
                keyData._indexToken,
                keyData._isLong
            );

        if (size == 0) {
            uint count = dataTracker.getDataCount(
                Integration.GMXPositions,
                address(this)
            );

            for (uint256 i = 0; i < count; i++) {
                GMXPositionData memory positionData = abi.decode(
                    dataTracker.getData(
                        Integration.GMXPositions,
                        address(this),
                        i
                    ),
                    (GMXPositionData)
                );
                if (
                    keyData._collateralToken == positionData._collateralToken &&
                    keyData._indexToken == positionData._indexToken &&
                    keyData._isLong == positionData._isLong
                ) {
                    dataTracker.removeData(Integration.GMXPositions, i);
                    break;
                }
            }
        }
    }

    /// @notice Can only be called from the vault
    /// @dev If we're not tracking the position adds it, during this function we check tracked position are still open
    /// @dev And if not remove them (they have likely been liquidated)
    function updatePositions(
        address _indexToken,
        address _collateralToken,
        bool _isLong,
        uint256 maxPositionsAllowed
    ) internal {
        Registry registry = VaultBaseExternal(address(this)).registry();
        IntegrationDataTracker dataTracker = registry.integrationDataTracker();
        require(
            address(dataTracker) != address(0),
            'no dataTracker configured'
        );
        removeExcutedRequests();

        bytes[] memory positionData = dataTracker.getAllData(
            Integration.GMXPositions,
            address(this)
        );
        bool positionIsTracked;
        for (uint256 i = positionData.length; i > 0; i--) {
            GMXPositionData memory keyData = abi.decode(
                positionData[i - 1],
                (GMXPositionData)
            );
            if (
                _indexToken == keyData._indexToken &&
                _collateralToken == keyData._collateralToken &&
                _isLong == keyData._isLong
            ) {
                positionIsTracked = true;
            }
            // Remove positions that are no longer open
            // i.e if they get liquidated
            // Note: if there is an active request for the position we don't remove it
            else {
                removePositionIfEmpty(keyData, i - 1);
            }
        }

        require(
            positionIsTracked ||
                dataTracker.getDataCount(
                    Integration.GMXPositions,
                    address(this)
                ) <
                maxPositionsAllowed,
            'GMX: max gmx positions reached'
        );

        if (!positionIsTracked) {
            dataTracker.pushData(
                Integration.GMXPositions,
                abi.encode(
                    GMXPositionData({
                        _collateralToken: _collateralToken,
                        _indexToken: _indexToken,
                        _isLong: _isLong
                    })
                )
            );
        }
    }

    /// @notice this should be uneccessary because the request should get removed when we receive
    ///         the callback from the GMXPositionRouter, but we have no guarantees on the callback
    ///         because it's wrapped in a try catch
    function removeExcutedRequests() internal {
        Registry registry = VaultBaseExternal(address(this)).registry();
        IntegrationDataTracker dataTracker = registry.integrationDataTracker();
        require(
            address(dataTracker) != address(0),
            'no dataTracker configured'
        );
        bytes[] memory positionData = dataTracker.getAllData(
            Integration.GMXRequests,
            address(this)
        );
        // Reverse loop is important because we're removing items from the array
        for (uint256 i = positionData.length; i > 0; i--) {
            (bytes32 storedKey, ) = abi.decode(
                positionData[i - 1],
                (bytes32, GMXRequestData)
            );

            (address account, , ) = GmxHelpers.getIncreasePositionRequestsData(
                registry.gmxConfig().positionRouter(),
                storedKey
            );
            if (account != address(this)) {
                removeRequest(registry, uint(i - 1));
            }
        }
    }

    /// @notice checks if there is an active request for the given position
    function hasActiveRequest(
        address vault,
        GMXPositionData memory positionKeyData
    ) internal view returns (bool) {
        Registry registry = VaultBaseExternal(vault).registry();
        IntegrationDataTracker dataTracker = registry.integrationDataTracker();
        require(
            address(dataTracker) != address(0),
            'no dataTracker configured'
        );

        bytes[] memory requests = dataTracker.getAllData(
            Integration.GMXRequests,
            vault
        );
        for (uint256 i = 0; i < requests.length; i++) {
            (, GMXRequestData memory requestKeyData) = abi.decode(
                requests[i],
                (bytes32, GMXRequestData)
            );

            if (
                positionKeyData._collateralToken ==
                requestKeyData._collateralToken &&
                positionKeyData._indexToken == requestKeyData._indexToken &&
                positionKeyData._isLong == requestKeyData._isLong
            ) {
                return true;
            }
        }
        return false;
    }

    /// @notice finds a GmxRequestData in storage by the key
    function findRequest(
        address vault,
        bytes32 key
    ) internal view returns (GMXRequestData memory, int256 index) {
        Registry registry = VaultBaseExternal(vault).registry();
        IntegrationDataTracker dataTracker = registry.integrationDataTracker();
        require(
            address(dataTracker) != address(0),
            'no dataTracker configured'
        );

        bytes[] memory positionData = dataTracker.getAllData(
            Integration.GMXRequests,
            vault
        );
        for (uint256 i = 0; i < positionData.length; i++) {
            (bytes32 storedKey, GMXRequestData memory keyData) = abi.decode(
                positionData[i],
                (bytes32, GMXRequestData)
            );

            if (storedKey == key) {
                return (keyData, int(i));
            }
        }
        return (
            GMXRequestData(
                address(0),
                address(0),
                address(0),
                address(0),
                false
            ),
            -1
        );
    }

    function getStoredPositionCount(
        address vault
    ) internal view returns (uint256) {
        Registry registry = VaultBaseExternal(vault).registry();
        IntegrationDataTracker dataTracker = registry.integrationDataTracker();
        require(
            address(dataTracker) != address(0),
            'no dataTracker configured'
        );
        return dataTracker.getDataCount(Integration.GMXPositions, vault);
    }

    /// @notice gets all GMXPositionData in storage for the vault
    function getStoredPositions(
        address vault
    ) internal view returns (GMXPositionData[] memory) {
        Registry registry = VaultBaseExternal(vault).registry();
        IntegrationDataTracker dataTracker = registry.integrationDataTracker();
        require(
            address(dataTracker) != address(0),
            'no dataTracker configured'
        );

        bytes[] memory positionData = registry
            .integrationDataTracker()
            .getAllData(Integration.GMXPositions, vault);
        GMXPositionData[] memory positions = new GMXPositionData[](
            positionData.length
        );
        for (uint256 i = 0; i < positionData.length; i++) {
            positions[i] = abi.decode(positionData[i], (GMXPositionData));
        }
        return positions;
    }

    /// @notice gets all GMXRequestData in storage for the vault
    function getStoredRequests(
        address vault
    ) internal view returns (GMXRequestData[] memory) {
        Registry registry = VaultBaseExternal(vault).registry();
        IntegrationDataTracker dataTracker = registry.integrationDataTracker();
        require(
            address(dataTracker) != address(0),
            'no dataTracker configured'
        );

        bytes[] memory requestsData = registry
            .integrationDataTracker()
            .getAllData(Integration.GMXRequests, vault);
        GMXRequestData[] memory requests = new GMXRequestData[](
            requestsData.length
        );

        for (uint256 i = 0; i < requestsData.length; i++) {
            (, GMXRequestData memory requestData) = abi.decode(
                requestsData[i],
                (bytes32, GMXRequestData)
            );
            requests[i] = requestData;
        }
        return requests;
    }
}

