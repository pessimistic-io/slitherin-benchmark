// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

/// @title IBaseRouteSetter
/// @dev Interface for BaseRouteSetter contract
interface IBaseRouteSetter {

    struct AddCollateralRequest {
        bool isAdjustmentRequired;
        uint256 puppetsAmountIn;
        uint256 traderAmountIn;
        uint256 traderShares;
        uint256 totalSupply;
        uint256 totalAssets;
        uint256[] puppetsShares;
        uint256[] puppetsAmounts;
    }

    struct TraderTargetLeverage {
        uint256 positionSize;
        uint256 positionCollateral;
        uint256 sizeIncrease;
        uint256 collateralIncrease;
    }

    struct RequestSharesData {
        uint256 positionIndex;
        uint256 totalSupply;
        uint256 totalAssets;
        uint256[] puppetsAmounts;
    }

    // route
    function initializePositionPuppets(uint256 _positionIndex, bytes32 _routeKey, address[] memory _puppets) external;
    function storeNewAddCollateralRequest(AddCollateralRequest memory _addCollateralRequest, uint256 _positionIndex, uint256 _addCollateralRequestsIndex, bytes32 _routeKey) external;
    function storeTargetLeverage(TraderTargetLeverage memory _traderTargetLeverage, uint256 _basisPointsDivisor, bytes32 _routeKey) external;
    function storeIncreasePositionRequest(uint256 _positionIndex, uint256 _addCollateralRequestsIndex, uint256 _amountIn, uint256 _sizeDelta, bytes32 _routeKey, bytes32 _requestKey) external;
    function storePnLOnSuccessfullDecrease(bytes32 _routeKey, int256 _puppetsPnL, int256 _traderAssets) external;
    function storePositionAmounts(uint256 _positionIndex, uint256 _totalSupply, uint256 _totalAssets, bytes32 _routeKey) external;
    function storeDecreasePositionRequest(uint256 _positionIndex, uint256 _sizeDelta, bytes32 _routeKey, bytes32 _requestKey) external;
    function storeKeeperRequest(bytes32 _routeKey, bytes32 _requestKey) external;
    function storeCumulativeVolumeGenerated(uint256 _cumulativeVolumeGenerated, bytes32 _routeKey) external;
    function addPuppetShares(uint256 _positionIndex, uint256 _puppetIndex, uint256 _newPuppetShares, uint256 _puppetAmountIn, int256 _puppetPnL, bytes32 _routeKey) external;
    function addPuppetsShares(uint256[] memory _puppetsAmounts, uint256 _positionIndex, uint256 _totalAssets, uint256 _totalSupply, bytes32 _routeKey) external returns (uint256, uint256);
    function addTraderShares(uint256 _positionIndex, uint256 _newTraderShares, uint256 _traderAmountIn, int256 _traderPnL, bytes32 _routeKey) external;
    function setAllocateShares(RequestSharesData memory _requestSharesData, uint256 _traderAmountIn, bytes32 _routeKey) external returns (uint256);
    function setIsKeeperAdjustmentEnabled(bytes32 _routeKey, bool _isKeeperAdjustmentEnabled) external;
    function setIsWaitingForKeeperAdjustment(bytes32 _routeKey, bool _isWaitingForKeeperAdjustment) external;
    function setAdjustmentFlags(bool _isAdjustmentRequired, bool _isExecuted, bool _isKeeperRequest, bytes32 _routeKey) external;
    function resetPuppetsArray(uint256 _positionIndex, bytes32 _routeKey) external;
    function resetRoute(bytes32 _routeKey) external;

    // ============================================================================================
    // Errors
    // ============================================================================================

    error Unauthorized();
}
