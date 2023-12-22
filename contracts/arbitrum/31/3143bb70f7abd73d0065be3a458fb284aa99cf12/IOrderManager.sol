pragma solidity >=0.8.0;

import {DataTypes} from "./DataTypes.sol";

interface IOrderManager {
    function placeLeverageOrder(
        DataTypes.UpdatePositionType _updateType,
        DataTypes.Side _side,
        address _indexToken,
        address _collateralToken,
        DataTypes.OrderType _orderType,
        bytes calldata data
    ) external payable returns (uint256 orderId);

    function executeLeverageOrder(uint256 _orderId, address payable _feeTo) external;

    function cancelLeverageOrder(uint256 _orderId) external;

    function placeSwapOrder(
        address _tokenIn,
        address _tokenOut,
        uint256 _amountIn,
        uint256 _minOut,
        uint256 _price,
        bytes calldata _extradata
    ) external payable returns (uint256 orderId);

    function executeSwapOrder(uint256 _orderId, address payable _feeTo) external;

    function cancelSwapOrder(uint256 _orderId) external;

    function swap(
        address _fromToken,
        address _toToken,
        uint256 _amountIn,
        uint256 _minAmountOut,
        bytes calldata extradata
    ) external payable;

    // ========== EVENTS =========

    event LeverageOrderPlaced(
        uint256 indexed key, DataTypes.LeverageOrder order, DataTypes.UpdatePositionRequest request
    );
    event LeverageOrderCancelled(uint256 indexed key);
    event LeverageOrderExecuted(
        uint256 indexed key, DataTypes.LeverageOrder order, DataTypes.UpdatePositionRequest request, uint256 fillPrice
    );
    event LeverageOrderExpired(uint256 indexed key);
    event SwapOrderPlaced(uint256 indexed key, DataTypes.SwapOrder order);
    event SwapOrderCancelled(uint256 indexed key);
    event SwapOrderExecuted(uint256 indexed key, uint256 amountIn, uint256 amountOut);
    event Swap(
        address indexed account,
        address indexed tokenIn,
        address indexed tokenOut,
        address pool,
        uint256 amountIn,
        uint256 amountOut
    );
    event OracleChanged(address);
    event PoolSet(address indexed pool);
    event MinLeverageExecutionFeeSet(uint256 leverageExecutionFee);
    event MinSwapExecutionFeeSet(uint256 swapExecutionFee);
    event OrderHookSet(address indexed hook);
    event ExecutorSet(address indexed executor);
    event ControllerSet(address indexed controller);
    event SetEnablePublicExecution(bool isEnable);
    event SetExecutionDelayTime(uint256 delay);

    // ======= ERRORS ========

    error OnlyExecutor();
    error OnlyWeth();
    error ZeroAddress();
    error InvalidExecutionFee();
    error InvalidLeverageTokenPair(address indexToken, address collateralToken);
    error InvalidSwapPair();
    error SameTokenSwap();
    error OnlyOrderOwner();
    error OrderNotOpen();
    error ExecutionDelay();
    error ExecutionFeeTooLow();
    error SlippageReached();
    error ZeroPurchaseAmount();
    error InvalidPurchaseToken();
    error OnlyOwnerOrController();
}

