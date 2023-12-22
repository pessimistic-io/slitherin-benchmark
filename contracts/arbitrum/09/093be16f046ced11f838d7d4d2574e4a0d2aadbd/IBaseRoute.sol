// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

// ==============================================================
//  _____                 _      _____ _                        |
// |  _  |_ _ ___ ___ ___| |_   |   __|_|___ ___ ___ ___ ___    |
// |   __| | | . | . | -_|  _|  |   __| |   | .'|   |  _| -_|   |
// |__|  |___|  _|  _|___|_|    |__|  |_|_|_|__,|_|_|___|___|   |
//           |_| |_|                                            |
// ==============================================================
// ========================= IBaseRoute =========================
// ==============================================================
// Puppet Finance: https://github.com/GMX-Blueberry-Club/puppet-contracts

// Primary Author
// johnnyonline: https://github.com/johnnyonline

// Reviewers
// itburnz: https://github.com/nissoh

// ==============================================================

interface IBaseRoute {

    struct AdjustPositionParams {
        uint256 collateralDelta;
        uint256 sizeDelta;
        uint256 acceptablePrice;
    }

    struct SwapParams {
        address[] path;
        uint256 amount;
        uint256 minOut;
    }

    // ============================================================================================
    // Mutated Functions
    // ============================================================================================

    // orchestrator

    // called by trader

    /// @notice The ```requestPosition``` function creates a new position request
    /// @param _adjustPositionParams The adjusment params for the position
    /// @param _swapParams The swap data of the Trader, enables the Trader to add collateral with a non-collateral token
    /// @param _executionFee The total execution fee, paid by the Trader in ETH
    /// @param _isIncrease The boolean indicating if the request is an increase or decrease request
    /// @return _requestKey The request key
    function requestPosition(AdjustPositionParams memory _adjustPositionParams, SwapParams memory _swapParams, uint256 _executionFee, bool _isIncrease) external payable returns (bytes32 _requestKey);

    // called by keeper

    /// @notice The ```decreaseSize``` function is called by Puppet keepers to decrease the position size in case there are Puppets to adjust
    /// @param _adjustPositionParams The adjusment params for the position
    /// @param _executionFee The total execution fee, paid by the Keeper in ETH
    /// @return _requestKey The request key
    function decreaseSize(AdjustPositionParams memory _adjustPositionParams, uint256 _executionFee) external payable returns (bytes32 _requestKey);

    /// @notice The ```liquidate``` function is called by Puppet keepers to reset the Route's accounting in case of a liquidation
    function liquidate() external;

    // called by owner

    /// @notice The ```rescueTokens``` is called by the Orchestrator and Authority to rescue tokens
    /// @param _amount The amount to rescue
    /// @param _token The token address
    /// @param _receiver The receiver address
    function rescueTokenFunds(uint256 _amount, address _token, address _receiver) external;

    // ============================================================================================
    // Events
    // ============================================================================================

    event Liquidate();
    event Callback(bytes32 requestKey, bool isExecuted, bool isIncrease);
    event IncreaseRequest(bytes32 requestKey, uint256 amountIn, uint256 sizeDelta, uint256 acceptablePrice);
    event DecreaseRequest(bytes32 requestKey, uint256 collateralDelta, uint256 sizeDelta, uint256 acceptablePrice);
    event Repay(uint256 totalAssets, uint256 performanceFeePaid);
    event RescueTokenFunds(uint256 amount, address token, address receiver);

    // ============================================================================================
    // Errors
    // ============================================================================================

    error WaitingForKeeperAdjustment();
    error NotKeeper();
    error NotTrader();
    error InvalidExecutionFee();
    error PositionStillAlive();
    error PositionNotOpen();
    error Paused();
    error NotOrchestrator();
    error RouteFrozen();
    error NotCallbackCaller();
    error NotWaitingForKeeperAdjustment();
    error ZeroAddress();
    error KeeperAdjustmentDisabled();
}
