// SPDX-License-Identifier: MIT
pragma solidity = 0.7.6;
pragma abicoder v2;

import "./ERC20.sol";
import "./Ownable.sol";
import "./SafeMath.sol";
import "./ReentrancyGuard.sol";
import "./Pausable.sol";
import "./Math.sol";
import "./ISwapRouter.sol";
import "./TransferHelper.sol";
import "./PoolAddress.sol";
import "./OracleLibrary.sol";
import "./IPeripheryImmutableState.sol";
import "./IUniswapV3Pool.sol";
import "./FixedPoint96.sol";
import "./IWETH.sol";

contract RecurringSwapV1 is Ownable, ReentrancyGuard, Pausable {
    using SafeMath for uint256;

    bytes constant public VERSION = bytes("1");

    uint24 constant ONE_DAY_SECONDS = 1 days;
    uint16[3] public POOL_FEES = [500, 3000, 10000];

    struct Order {
        uint256 nonce;
        address signer;
        address dstReceiver;
        address fromToken;
        address toToken;
        uint256 fromTokenAmount;
        uint8 frequency;
    }

    struct OrderData {
        bytes32 orderHash;
        uint256 nextSwap;
        Order order;
    }

    event NewOrder(
        Order order,
        bytes32 indexed orderHash,
        uint256 initSwapTimestamp
    );

    struct SwapData {
        bytes32 orderHash;
        uint256 fromTokenUsdcValue;
        uint24 poolFee;
        uint256 amountOut;
        uint256 txFee;
        uint256 lastSwap;
    }

    event ExecuteSwap(
        SwapData[] swap,
        uint256 timestamp
    );

    event CancelOrder(
        address indexed account,
        bytes32 indexed orderHash
    );

    mapping(bytes32 => OrderData) public orders;
    mapping(address => bool) public operators;
    mapping(address => uint256) public nonces;

    address public weth;
    ISwapRouter public swapRouter;
    address public usdc;
    uint256 public minAmountInUsdc;

    modifier onlyOperators() {
        require(operators[msg.sender], "Swap: access denied");
        _;
    }

    constructor(ISwapRouter _swapRouter, address _usdc, uint256 _minAmountInUsdc) {
        setupOperator(msg.sender, true);
        swapRouter = _swapRouter;
        weth = IPeripheryImmutableState(address(swapRouter)).WETH9();
        usdc = _usdc;
        minAmountInUsdc = _minAmountInUsdc;
    }

    receive() external payable {}

    function pause() public onlyOwner whenNotPaused {
        super._pause();
    }

    function unpause() public onlyOwner whenPaused {
        super._unpause();
    }

    function setupOperator(address operator, bool access) public onlyOwner {
        operators[operator] = access;
    }

    function setMinAmountInUsdc(uint256 _minAmountInUsdc) public onlyOwner {
        minAmountInUsdc = _minAmountInUsdc;
    }

    function getCurrentRoundedDate() public view returns (uint256) {
        return block.timestamp.div(ONE_DAY_SECONDS).mul(ONE_DAY_SECONDS);
    }

    function createOrder(Order calldata order) public {
        bytes32 orderHash = hash(order);
        require(order.fromToken != address(0) && order.toToken != address(0), 'RecurringSwap:wrong token address');
        require(order.fromToken != order.toToken, 'RecurringSwap:wrong swap tokens');
        require(order.dstReceiver != address(0), 'RecurringSwap:wrong tokens receiver');
        require(msg.sender == order.signer, 'RecurringSwap:wrong singer');
        require(order.fromTokenAmount > 0, 'RecurringSwap:wrong amount');
        require(order.frequency > 0, 'RecurringSwap:wrong frequency');
        require(nonces[msg.sender] + 1 == order.nonce, 'RecurringSwap:wrong nonce');

        uint256 amountInUsdc = calculateAmountOut(order.fromToken, usdc, order.fromTokenAmount);
        require(amountInUsdc >= minAmountInUsdc, 'RecurringSwap:wrong min amount');

        (, IUniswapV3Pool pool) = findPool(order.fromToken, order.toToken);
        require(address(pool) != address(0), 'RecurringSwap:pool not found');

        uint256 currentRoundedTimestamp = getCurrentRoundedDate();

        nonces[msg.sender]++;

        orders[orderHash] = OrderData(
            orderHash,
            currentRoundedTimestamp + ONE_DAY_SECONDS, // first exchange next day
            order
        );

        emit NewOrder(order, orderHash, currentRoundedTimestamp);
    }

    function recurringSwap(
        bytes32[] calldata orderHashas
    ) public onlyOperators nonReentrant whenNotPaused payable returns (bytes32[] memory successOrders){
        uint256 startGas = gasleft();
        require(orderHashas.length > 0, 'RecurringSwap:empty data for swap');

        SwapData[] memory swapData = new SwapData[](orderHashas.length);
        successOrders = new bytes32[](orderHashas.length);
        uint256 index = 0;
        OrderData storage orderData;
        uint256 roundedDate = getCurrentRoundedDate();

        for (uint i = 0; i < orderHashas.length; i++) {
            orderData = orders[orderHashas[i]];

            if (block.timestamp >= orderData.nextSwap) {
                (bool successSwap, uint256 amountOut, uint24 poolFee) = swap(orderData.order);

                if (!successSwap || amountOut == 0) {
                    continue;
                }

                uint256 fromTokenUsdcValue = calculateAmountOut(
                    orderData.order.fromToken,
                    usdc,
                    orderData.order.fromTokenAmount
                );

                uint256 step = (orderData.order.frequency * ONE_DAY_SECONDS);
                orderData.nextSwap += (roundedDate - orderData.nextSwap).div(step).mul(step) + step;

                swapData[index] = SwapData(
                        orderData.orderHash,
                        fromTokenUsdcValue,
                        poolFee,
                        amountOut,
                        0,
                        roundedDate
                    );

                index++;
            }
        }

        require(index > 0, 'RecurringSwap:nothing for swap');

        //empirical gas calculations
        uint256 used = startGas
        .add(21000 + 16 * (msg.data.length - 68))
        .add(56301)
        .add(orderHashas.length * 82)
        .add((index - 1) * 19278)
        .sub(index > 1 ? 1545 : 0);

        uint256 gasUsed = used.sub(gasleft());

        uint256 usedPerOrder = gasUsed.mul(tx.gasprice).div(index);
        uint256 refund = 0;
        uint256 value;

        for (uint i = 0; i < index; i++) {
            orderData = orders[swapData[i].orderHash];
            value = getEthFromWethSilentOnError(orderData.order.signer, usedPerOrder);
            refund += value;

            if (value > 0) {
                swapData[i].txFee = value;
                successOrders[i] = orderData.orderHash;
            } else {
                delete swapData[i];
            }
        }

        IWETH(weth).withdraw(refund);
        (bool transaferSuccess,) = msg.sender.call{value : refund}('');
        require(transaferSuccess, 'RecurringSwap:Transfer failed');

        emit ExecuteSwap(swapData, block.timestamp);
    }

    function calculateAmountOut(address fromToken, address toToken, uint256 amountIn) public view returns (uint256) {
        if (fromToken == toToken) {
            return amountIn;
        }

        (, IUniswapV3Pool pool) = findPool(fromToken, toToken);

        if (address(pool) == address(0)) {
            return 0;
        }

        (uint160 sqrtPriceX96,,,,,,) = pool.slot0();

        uint256 originalAmount0 = FullMath.mulDiv(pool.liquidity(), FixedPoint96.Q96, sqrtPriceX96);
        uint256 originalAmount1 = FullMath.mulDiv(pool.liquidity(), sqrtPriceX96, FixedPoint96.Q96);

        uint256 amount0 = fromToken == pool.token0() ? originalAmount0 : originalAmount1;
        uint256 amount1 = fromToken == pool.token0() ? originalAmount1 : originalAmount0;

        uint numerator = amountIn.mul(amount1);
        uint denominator = amount0.add(amountIn);
        uint amountOut = numerator / denominator;

        return amountOut;
    }

    function swap(Order memory order) internal returns (bool, uint256, uint24){
        (uint24 poolFee, IUniswapV3Pool pool) = findPool(order.fromToken, order.toToken);

        if (address(pool) == address(0) || poolFee == 0) {
            return (false, 0, 0);
        }

        (bool successTransfer, bytes memory dataTransfer) = order.fromToken.call(
            abi.encodeWithSelector(
                ERC20.transferFrom.selector,
                order.signer,
                address(this),
                order.fromTokenAmount
            )
        );

        if (!(successTransfer && (dataTransfer.length == 0 || abi.decode(dataTransfer, (bool))))) {
            return (false, 0, 0);
        }

        TransferHelper.safeApprove(
            order.fromToken,
            address(swapRouter),
            order.fromTokenAmount
        );

        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn : order.fromToken,
            tokenOut : order.toToken,
            fee : poolFee,
            recipient : order.dstReceiver,
            deadline : block.timestamp,
            amountIn : order.fromTokenAmount,
            amountOutMinimum : 0,
            sqrtPriceLimitX96 : 0
            });

        (bool successSwap, bytes memory dataSwap) = address(swapRouter).call(
            abi.encodeWithSelector(ISwapRouter.exactInputSingle.selector, params)
        );

        if (!successSwap) {
            // return tokens to user when swap failed.
            TransferHelper.safeApprove(order.fromToken, address(swapRouter), 0);

            TransferHelper.safeTransferFrom(
                order.fromToken,
                address(this),
                order.signer,
                order.fromTokenAmount
            );
            return (false, 0, 0);
        }

        return (true, abi.decode(dataSwap, (uint256)), poolFee);
    }

    function findPool(address fromToken, address toToken) public view returns (uint24 poolFee, IUniswapV3Pool pool) {
        address factory = IPeripheryImmutableState(address(swapRouter)).factory();
        poolFee = 0;
        pool = IUniswapV3Pool(address(0));

        for (uint8 i = 0; i < POOL_FEES.length; i++) {
            pool = getPool(factory, fromToken, toToken, POOL_FEES[i]);

            if (address(pool) != address(0) && pool.liquidity() > 0) {
                poolFee = pool.fee();

                return (poolFee, pool);
            }
        }
    }

    function getPool(address factory, address tokenA, address tokenB, uint24 fee) private pure returns (IUniswapV3Pool) {
        return IUniswapV3Pool(PoolAddress.computeAddress(factory, PoolAddress.getPoolKey(tokenA, tokenB, fee)));
    }

    function cancelOrder(bytes32 orderHash) public {
        OrderData memory data = orders[orderHash];

        require(data.order.signer == msg.sender, 'Swap:Access denied');

        delete orders[orderHash];
        emit CancelOrder(msg.sender, orderHash);
    }

    function hash(Order calldata _order) public pure returns (bytes32) {
        return keccak256(
            abi.encode(
                _order.nonce,
                _order.signer,
                _order.dstReceiver,
                _order.fromToken,
                _order.toToken,
                _order.fromTokenAmount,
                _order.frequency
            )
        );
    }

    function getEthFromWethSilentOnError(address from, uint256 value) internal returns (uint256) {
        (bool successTransfer, bytes memory dataTransfer) = weth.call(
            abi.encodeWithSelector(
                ERC20.transferFrom.selector,
                from,
                address(this),
                value
            )
        );

        if (successTransfer && (dataTransfer.length == 0 || abi.decode(dataTransfer, (bool)))) {
            return value;
        }

        return 0;
    }
}

