//SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

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

    function createExitStrategyOrder(
        uint256 _positionId,
        bool _exitLongPosition
    ) external payable;

    function createIncreaseManagedPositionOrder(
        uint256 _positionId
    ) external payable;

    event StrategyEnabled(
        uint256 positionId,
        uint256 putstrike,
        uint256 optionsAmount
    );
    event OrderCreated(uint256 positionId, ActionState _newState);
    event StrategyFeesCollected(uint256 fees);
    event MaxLeverageSet(uint256 _maxLeverage);
    event KeeperHandleWindowSet(uint256 _window);
    event KeeperSet(address _keeper, bool setAs);
    event AddressesSet(
        address _feeDistributor,
        address _utils,
        address _positionManagerFactory,
        address _gov,
        address _feeStrategy
    );

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

