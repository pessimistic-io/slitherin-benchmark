//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.7;

interface IInsuredLongsStrategy {
    function gmxPositionCallback(
        bytes32 positionKey,
        bool isExecuted,
        bool
    ) external payable;

    function positionsCount() external view returns (uint256);

    function getStrategyPosition(
        uint256 _positionId
    )
        external
        view
        returns (
            uint256,
            uint256,
            address,
            address,
            address,
            bool,
            ActionState
        );

    function isManagedPositionDecreasable(
        uint256 _positionId
    ) external view returns (bool isDecreasable);

    function isManagedPositionLiquidatable(
        uint256 _positionId
    ) external view returns (bool isLiquidatable);

    function createExitStrategyOrder(
        uint256 _positionId,
        bool exitLongPosition
    ) external payable;

    function createIncreaseManagedPositionOrder(
        uint256 _positionId
    ) external payable;

    function emergencyStrategyExit(uint256 _positionId) external;

    event AtlanticPoolWhitelisted(
        address _poolAddress,
        address _quoteToken,
        address _indexToken,
        uint256 _expiry,
        uint256 _tickSizeMultiplier
    );
    event UseStrategy(uint256 _positionId);
    event StrategyPositionEnabled(uint256 _positionId);
    event ManagedPositionIncreaseOrderSuccess(uint256 _positionId);
    event ManagedPositionExitStrategy(uint256 _positionId);
    event CreateExitStrategyOrder(uint256 _positionId);
    event ReuseStrategy(uint256 _positionId);
    event EmergencyStrategyExit(uint256 _positionId);
    event LiquidationCollateralMultiplierBpsSet(uint256 _multiplierBps);
    event KeepCollateralEnabled(uint256 _positionId);
    event FeeWithdrawn(address _token, uint256 _amount);
    event UseDiscountForFeesSet(bool _setAs);

    error InsuredLongsStrategyError(uint256 _errorCode);

    enum ActionState {
        None, // 0
        Settled, // 1
        Active, // 2
        IncreasePending, // 3
        Increased, // 4
        EnablePending, // 5
        ExitPending // 6
    }

    struct StrategyPosition {
        uint256 expiry;
        uint256 atlanticsPurchaseId;
        address indexToken;
        address collateralToken;
        address user;
        bool keepCollateral;
        ActionState state;
    }
}

