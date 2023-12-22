pragma solidity >=0.6.6;

import "./IUniswapV2Pair.sol";
import "./IUniswapV2Factory.sol";
import "./ISwapRouter.sol";
import "./IUniswapV3SwapCallback.sol";
import "./IUniswapV3PoolActions.sol";
import "./IWETH.sol";
import "./TransferHelper.sol";
import "./TickMath.sol";

library SafeMath {
    function add(uint x, uint y) internal pure returns (uint z) {
        require((z = x + y) >= x, 'ds-math-add-overflow');
    }

    function sub(uint x, uint y) internal pure returns (uint z) {
        require((z = x - y) <= x, 'ds-math-sub-underflow');
    }

    function mul(uint x, uint y) internal pure returns (uint z) {
        require(y == 0 || (z = x * y) / y == x, 'ds-math-mul-overflow');
    }
}

contract CexDexArbV5 is IUniswapV3SwapCallback {
    using SafeMath for uint256;

    address public immutable owner;
    address public immutable weth;

    mapping(address => bool) private senderWhitelist;
    mapping(address => bool) private pairWhitelist;
    address currentPair;

    constructor(address _owner, address _weth, address[] memory senderList, address[] memory pairList) {
        owner = _owner;
        weth = _weth;
        addWhitelist(senderList, pairList);
    }
    function AddWhitelist(address[] memory senderList, address[] memory pairList) public onlyOwner {
        addWhitelist(senderList, pairList);
    }

    function addWhitelist(address[] memory senderList, address[] memory pairList) private {
        for (uint256 i = 0; i < senderList.length; i++) {
            senderWhitelist[senderList[i]] = true;
        }
        for (uint256 i = 0; i < pairList.length; i++) {
            pairWhitelist[pairList[i]] = true;
        }
    }

    receive() external payable {}

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }
    modifier onlySender() {
        require(senderWhitelist[msg.sender], "Not allow sender");
        _;
    }
    modifier onlyPair(address pair) {
        require(pairWhitelist[pair], "Not allow pair");
        _;
    }

    function withdrawETH() public onlyOwner {
        TransferHelper.safeTransferETH(owner, address(this).balance);
    }

    function swapExactIn(address tokenIn, address tokenOut, address pair, uint256 feeR,
        uint256 amountIn, uint256 amountOutMin) public onlySender onlyPair(pair) {

        (uint112 r0, uint112 r1, uint32 blockTimestampLast) = IUniswapV2Pair(pair).getReserves();
        uint256 amountOut = tokenIn < tokenOut ? getAmountOut(amountIn, r0, r1, feeR) : getAmountOut(amountIn, r1, r0, feeR);
        require(amountOut >= amountOutMin, "K");
        TransferHelper.safeTransferFrom(tokenIn, owner, pair, amountIn);
        (uint256 amount0Out, uint256 amount1Out) = tokenIn < tokenOut ? (uint(0), amountOut) : (amountOut, uint(0));
        IUniswapV2Pair(pair).swap(amount0Out, amount1Out, owner, new bytes(0));
    }

    function swapExactOut(address tokenIn, address tokenOut, address pair, uint256 feeR,
        uint256 amountInMax, uint256 amountOut) public onlySender onlyPair(pair) {
        (uint112 r0, uint112 r1, uint32 blockTimestampLast) = IUniswapV2Pair(pair).getReserves();
        uint256 amountIn = tokenIn < tokenOut ? getAmountIn(amountOut, r0, r1, feeR) : getAmountIn(amountOut, r1, r0, feeR);
        require(amountIn <= amountInMax, "K");
        TransferHelper.safeTransferFrom(tokenIn, owner, pair, amountIn);
        (uint256 amount0Out, uint256 amount1Out) = tokenIn < tokenOut ? (uint(0), amountOut) : (amountOut, uint(0));
        IUniswapV2Pair(pair).swap(amount0Out, amount1Out, owner, new bytes(0));
    }

    function swapV3ExactIn(address tokenIn, address tokenOut, address pair, uint256 feeR,
        uint256 amountIn, uint256 amountOutMin) public onlySender onlyPair(pair) {
        currentPair = pair;
        bool zeroForOne = tokenIn < tokenOut;

        (address t0,address t1) = zeroForOne ? (tokenIn, tokenOut) : (tokenOut, tokenIn);
        (int256 amount0, int256 amount1) = IUniswapV3PoolActions(pair).swap(
            owner,
            zeroForOne,
            int256(amountIn),
            (zeroForOne ? TickMath.MIN_SQRT_RATIO + 1 : TickMath.MAX_SQRT_RATIO - 1),
            abi.encode(address(this), t0, t1)
        );

        uint256 amountOut = uint256(- (zeroForOne ? amount1 : amount0));
        require(amountOut >= amountOutMin, "K");

    }

    function swapV3ExactOut(address tokenIn, address tokenOut, address pair, uint256 feeR,
        uint256 amountInMax, uint256 amountOut) public onlySender onlyPair(pair) {
        currentPair = pair;
        bool zeroForOne = tokenIn < tokenOut;
        (address t0,address t1) = zeroForOne ? (tokenIn, tokenOut) : (tokenOut, tokenIn);
        (int256 amount0Delta, int256 amount1Delta) = IUniswapV3PoolActions(pair).swap(
            owner,
            zeroForOne,
            - int256(amountOut),
            (zeroForOne ? TickMath.MIN_SQRT_RATIO + 1 : TickMath.MAX_SQRT_RATIO - 1),
            abi.encode(address(this), t0, t1)
        );

        uint256 amountIn = zeroForOne ? uint256(amount0Delta) : uint256(amount1Delta);
        require(amountIn <= amountInMax, "K");
    }

    function uniswapV3SwapCallback(
        int256 amount0Delta,
        int256 amount1Delta,
        bytes calldata data
    ) external override {
        (address sender,address t0,address t1) = abi.decode(data, (address, address, address));

        require(msg.sender == currentPair);
        require(pairWhitelist[currentPair], "Not allow pair");
        require(sender == address(this));
        if (amount0Delta > 0) {
            TransferHelper.safeTransferFrom(t0, owner, currentPair, uint256(amount0Delta));
        }
        if (amount1Delta > 0) {
            TransferHelper.safeTransferFrom(t1, owner, currentPair, uint256(amount1Delta));
        }

    }

    function getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut, uint256 feeR) internal pure returns (uint256 amountOut) {
        require(amountIn > 0, 'UniswapV2Library: INSUFFICIENT_INPUT_AMOUNT');
        require(reserveIn > 0 && reserveOut > 0, 'UniswapV2Library: INSUFFICIENT_LIQUIDITY');
        uint256 amountInWithFee = amountIn.mul(feeR);
        uint256 numerator = amountInWithFee.mul(reserveOut);
        uint256 denominator = reserveIn.mul(10000).add(amountInWithFee);
        amountOut = numerator / denominator;
    }

    function getAmountIn(uint256 amountOut, uint256 reserveIn, uint256 reserveOut, uint256 feeR) internal pure returns (uint256 amountIn) {
        require(amountOut > 0, 'UniswapV2Library: INSUFFICIENT_OUTPUT_AMOUNT');
        require(reserveIn > 0 && reserveOut > 0, 'UniswapV2Library: INSUFFICIENT_LIQUIDITY');
        uint256 numerator = reserveIn.mul(amountOut).mul(10000);
        uint256 denominator = reserveOut.sub(amountOut).mul(feeR);
        amountIn = (numerator / denominator).add(1);
    }

}

