// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.19;

import "./IERC20.sol";
import "./SafeERC20.sol";
import "./SafeMath.sol";
import "./SignedSafeMath.sol";
import "./ISwapRouter.sol";
import "./TransferHelper.sol";
import "./ReentrancyGuard.sol";
import "./IUniswapV3Pool.sol";
import "./ReentrancyGuard.sol";
import "./AccessControl.sol";

import "./IDEXPool.sol";
import "./TickMath.sol";
import "./FullMath.sol";
import "./LiquidityAmounts.sol";
import "./PositionValue.sol";
import "./INonfungiblePositionManager.sol";

contract UniV3Pool is IDEXPool, ReentrancyGuard, AccessControl {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;
    using SignedSafeMath for int256;

    bytes32 public constant VAULT_ROLE = keccak256("VAULT_ROLE");

    ISwapRouter public immutable _swapRouter;
    IUniswapV3Pool public immutable _swapPool;
    IERC20 public immutable _token0;
    IERC20 public immutable _token1;
    uint24 private _poolFee;

    INonfungiblePositionManager public immutable _positionManager;

    uint256 public _tokenId;

    uint256 public constant PRECISION = 1e36;

    event Swap(address indexed fromToken, address indexed toToken, uint256 amountIn, uint256 amountOut, address indexed recipient);
    event LiquidityPositionMint(uint256 tokenId, uint256 amount0, uint256 amount1, address indexed sender, uint128 liquidity);
    event LiquidityIncreased(uint256 tokenId, uint256 amount0, uint256 amount1, address indexed sender);
    event LiquidityDecreased(uint256 tokenId, uint256 amount0, uint256 amount1, address indexed sender);
    event CollectedFees(uint256 tokenId, uint256 amount0, uint256 amount1, address indexed sender);

    modifier needPosition() {
        require(_tokenId != 0, "No liquidity position exists");
        _;
    }

    modifier whenNoPosition() {
        require(_tokenId == 0, "Liquidity position already exists");
        _;
    }

    constructor(
        address routerAddress,
        address poolAddress,
        address positionManagerAddress
    ) {
        _swapRouter = ISwapRouter(routerAddress);
        _swapPool = IUniswapV3Pool(poolAddress);
        _poolFee = _swapPool.fee();
        _token0 = IERC20(_swapPool.token0());
        _token1 = IERC20(_swapPool.token1());
        _positionManager = INonfungiblePositionManager(positionManagerAddress);

        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(VAULT_ROLE, msg.sender);
    }
    
    function supportsInterface(bytes4 interfaceId) public view override(AccessControl, IERC165) returns (bool) {
        return interfaceId == type(IDEXPool).interfaceId || super.supportsInterface(interfaceId);
    }

    function swapExactInputSingle(
        IERC20 from,
        IERC20 to,
        uint256 amountIn
    ) external onlyRole(VAULT_ROLE) returns (uint256 amountOut) {
        require(from.balanceOf(msg.sender) >= amountIn, "Insufficient balance");

        // Transfer the specified amount of from token to this contract.
        TransferHelper.safeTransferFrom(address(from), msg.sender, address(this), amountIn);

        // Approve the router to spend from token.
        TransferHelper.safeApprove(address(from), address(_swapRouter), amountIn);

        // Naively set amountOutMinimum to 0. Try to use an oracle or other data source to choose a safer value for amountOutMinimum.
        // We also set the sqrtPriceLimitx96 to be 0 to ensure we swap our exact input amount.
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter
            .ExactInputSingleParams({
                tokenIn: address(from),
                tokenOut: address(to),
                fee: _poolFee,
                recipient: msg.sender,
                deadline: block.timestamp,
                amountIn: amountIn,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            });

        // The call to `exactInputSingle` executes the swap.
        amountOut = _swapRouter.exactInputSingle(params);

        // Events
        emit Swap(address(from), address(to), amountIn, 0, msg.sender);
    }

    function swapExactOutputSingle(
        IERC20 from,
        IERC20 to,
        uint256 amountOut,
        uint256 amountInMaximum
    ) external onlyRole(VAULT_ROLE) returns (uint256 amountIn) {
        // Transfer the specified amount of from token to this contract.
        TransferHelper.safeTransferFrom(address(from), msg.sender, address(this), amountInMaximum);

        // Approve the router to spend from token.
        TransferHelper.safeApprove(address(from), address(_swapRouter), amountInMaximum);

        ISwapRouter.ExactOutputSingleParams memory params = ISwapRouter
            .ExactOutputSingleParams({
                tokenIn: address(from),
                tokenOut: address(to),
                fee: _poolFee,
                recipient: msg.sender,
                deadline: block.timestamp,
                amountOut: amountOut,
                amountInMaximum: amountInMaximum,
                sqrtPriceLimitX96: 0
            });

        // Executes the swap returning the amountIn needed to spend to receive the desired amountOut.
        amountIn = _swapRouter.exactOutputSingle(params);

        // For exact output swaps, the amountInMaximum may not have all been spent.
        // If the actual amount spent (amountIn) is less than the specified maximum amount, we must refund the msg.sender and approve the swapRouter to spend 0.
        if (amountIn < amountInMaximum) {
            TransferHelper.safeApprove(address(from), address(_positionManager), 0);
            TransferHelper.safeTransfer(address(from), msg.sender, amountInMaximum.sub(amountIn));
        }

        // Events
        emit Swap(address(from), address(to), 0, amountOut, msg.sender);
    }

    function getPoolFee() public view returns (uint24 fee) {
        fee = _poolFee;
    }

    function getPrice() public view returns (uint256 price) {
        (uint160 sqrtPriceX96, , , , , , ) = _swapPool.slot0();
        price = FullMath.mulDiv(sqrtPriceX96, sqrtPriceX96, FixedPoint96.Q96);
    }

    function getPrecision() public pure returns (uint256 precision) {
        precision = PRECISION;
    }

    function getTotalLiquidity() public view returns (uint128 liquidity) {
        if (_tokenId == 0) return 0;

        (, , , , , , , liquidity, , , , ) = _positionManager.positions( _tokenId);
    }

    function getTicks() public view returns (int24 tickLower, int24 tickUpper) {
        (, , , , , tickLower, tickUpper, , , , , ) = _positionManager.positions(_tokenId);
    }
    
    function getTokenAmounts(bool includeFee) public view returns (uint256[] memory amounts) {
        amounts = new uint256[](2);

        if (_tokenId == 0) return amounts;

        // Get the current square root price from the pool
        (uint160 sqrtPriceX96, , , , , , ) = _swapPool.slot0();

        (amounts[0], amounts[1]) = includeFee ? PositionValue.total(_positionManager, _tokenId, sqrtPriceX96) : PositionValue.principal(_positionManager, _tokenId, sqrtPriceX96);
    }

    function getTokens() public view returns (address[] memory tokens) {
        tokens = new address[](2);
        tokens[0] = address(_token0);
        tokens[1] = address(_token1);
    }

    function getTokenId() external view returns (uint256 tokenId) {
        return _tokenId;
    }

    function splitFundsIntoTokens(
        uint256 lowerPriceSqrtX96,
        uint256 upperPriceSqrtX96,
        uint256 funds,
        bool isFundsInToken0
    ) external view returns (uint256 token0Amount, uint256 token1Amount) {
        (uint160 sqrtPriceX96, , , , , , ) = _swapPool.slot0();

        // Out of range
        if (lowerPriceSqrtX96 > sqrtPriceX96 || sqrtPriceX96 > upperPriceSqrtX96) return (0, 0); 

        uint256 lowerPriceTermX96 = FullMath.mulDiv(
            sqrtPriceX96 - lowerPriceSqrtX96,
            upperPriceSqrtX96,
            FixedPoint96.Q96
        );

        uint256 upperPriceTermX96 = FullMath.mulDiv(
            sqrtPriceX96,
            upperPriceSqrtX96 - sqrtPriceX96,
            FixedPoint96.Q96
        );

        uint256 price = FullMath.mulDiv(sqrtPriceX96, sqrtPriceX96, FixedPoint96.Q96);

        // Fund token is token0
        if (isFundsInToken0) {
            token1Amount = FullMath.mulDiv(
                FullMath.mulDiv(funds, price, FixedPoint96.Q96),
                lowerPriceTermX96,
                lowerPriceTermX96 + upperPriceTermX96
            );

            token0Amount = funds - FullMath.mulDiv(token1Amount, FixedPoint96.Q96, price);
        } 
        // Fund token is token1
        else {
            token0Amount = FullMath.mulDiv(
                FullMath.mulDiv(funds, FixedPoint96.Q96, price),
                upperPriceTermX96,
                lowerPriceTermX96 + upperPriceTermX96
            );

            token1Amount = funds - FullMath.mulDiv(token0Amount, price, FixedPoint96.Q96);
        }
    }

    function getFeesToCollect()
        external
        view
        returns (uint256 feesCollectable0, uint256 feesCollectable1)
    {
        if (_tokenId == 0) return (0, 0);

        (feesCollectable0, feesCollectable1) = PositionValue.fees(_positionManager, _tokenId);
    }

    function mintNewPosition(
        uint256 amount0ToMint,
        uint256 amount1ToMint,
        int24 tickLower,
        int24 tickUpper,
        address leftOverRefundAddress
    )
        external
        onlyRole(VAULT_ROLE)
        whenNoPosition
        nonReentrant
        returns (
            uint256 tokenId,
            uint128 liquidity,
            uint256 amount0,
            uint256 amount1
        )
    {
        // transfer tokens to contract
        TransferHelper.safeTransferFrom(address(_token0), msg.sender, address(this), amount0ToMint);
        TransferHelper.safeTransferFrom(address(_token1), msg.sender, address(this), amount1ToMint);

        // Approve the position manager
        TransferHelper.safeApprove(address(_token0), address(_positionManager), amount0ToMint);
        TransferHelper.safeApprove(address(_token1), address(_positionManager), amount1ToMint);

        INonfungiblePositionManager.MintParams
            memory params = INonfungiblePositionManager.MintParams({
                token0: address(_token0),
                token1: address(_token1),
                fee: _poolFee,
                tickLower: tickLower,
                tickUpper: tickUpper,
                amount0Desired: amount0ToMint,
                amount1Desired: amount1ToMint,
                amount0Min: 0,
                amount1Min: 0,
                recipient: address(this),
                deadline: block.timestamp
            });

        (tokenId, liquidity, amount0, amount1) = _positionManager.mint(params);

        _tokenId = tokenId;

        emit LiquidityPositionMint(tokenId, amount0, amount1, msg.sender, liquidity);

        // Remove allowance and refund in both assets.
        if (amount0 < amount0ToMint) {
            TransferHelper.safeApprove(address(_token0), address(_positionManager), 0);
            uint256 refund0 = amount0ToMint.sub(amount0);
            TransferHelper.safeTransfer(address(_token0), leftOverRefundAddress, refund0);
        }

        if (amount1 < amount1ToMint) {
            TransferHelper.safeApprove(address(_token1), address(_positionManager), 0);
            uint256 refund1 = amount1ToMint.sub(amount1);
            TransferHelper.safeTransfer(address(_token1), leftOverRefundAddress, refund1);
        }
    }

    /// @notice Increases liquidity in the current range
    /// @dev Pool must be initialized already to add liquidity
    /// @param amount0 The amount to add of token0
    /// @param amount1 The amount to add of token1
    function increaseLiquidity(
        uint256 amount0Desired,
        uint256 amount1Desired,
        address leftOverRefundAddress
    )
        external
        onlyRole(VAULT_ROLE)
        needPosition
        returns (uint128 liquidity, uint256 amount0, uint256 amount1)
    {
        TransferHelper.safeTransferFrom(address(_token0), msg.sender, address(this), amount0Desired);
        TransferHelper.safeTransferFrom(address(_token1), msg.sender, address(this), amount1Desired);

        TransferHelper.safeApprove(address(_token0), address(_positionManager), amount0Desired);
        TransferHelper.safeApprove(address(_token1), address(_positionManager), amount1Desired);

        INonfungiblePositionManager.IncreaseLiquidityParams
            memory params = INonfungiblePositionManager
                .IncreaseLiquidityParams({
                    tokenId: _tokenId,
                    amount0Desired: amount0Desired,
                    amount1Desired: amount1Desired,
                    amount0Min: 0,
                    amount1Min: 0,
                    deadline: block.timestamp
                });

        (liquidity, amount0, amount1) = _positionManager.increaseLiquidity(
            params
        );

        // Remove allowance and refund in both assets.
        if (amount0 < amount0Desired) {
            TransferHelper.safeApprove(address(_token0), address(_positionManager), 0);
            uint256 refund0 = amount0Desired - amount0;
            TransferHelper.safeTransfer(address(_token0), leftOverRefundAddress, refund0);
        }

        if (amount1 < amount1Desired) {
            TransferHelper.safeApprove(address(_token1), address(_positionManager), 0);
            uint256 refund1 = amount1Desired - amount1;
            TransferHelper.safeTransfer(address(_token1), leftOverRefundAddress, refund1);
        }

        emit LiquidityIncreased(liquidity, amount0Desired, amount1Desired, msg.sender);
    }

    function decreaseLiquidity(
        uint128 liquidity,
        uint256 amount0Min,
        uint256 amount1Min
    )
        external
        onlyRole(VAULT_ROLE)
        needPosition
        returns (uint256 amount0, uint256 amount1)
    {
        require(liquidity > 0, "Liquidity must be greater than 0");

        INonfungiblePositionManager.DecreaseLiquidityParams
            memory params = INonfungiblePositionManager
                .DecreaseLiquidityParams({
                    tokenId: _tokenId,
                    liquidity: liquidity,
                    amount0Min: amount0Min,
                    amount1Min: amount1Min,
                    deadline: block.timestamp
                });

        (amount0, amount1) = _positionManager.decreaseLiquidity(params);

        // It is extremely unlikely that the amount of tokens corresponding to the decreasedLiquidity would exceed the uint128 range. But just to be safe.
        require(amount0 <= type(uint128).max, "amount0 is too large");
        require(amount1 <= type(uint128).max, "amount1 is too large");
        collect(address(this), uint128(amount0), uint128(amount1));

        // Transfer the removed tokens to the caller
        _token0.safeTransfer(msg.sender, amount0);
        _token1.safeTransfer(msg.sender, amount1);

        // Events
        emit LiquidityDecreased(_tokenId, amount0, amount1, msg.sender);
    }

    function collect(
        address recipient,
        uint128 amount0Max,
        uint128 amount1Max
    )
        public
        onlyRole(VAULT_ROLE)
        returns (uint256 amount0, uint256 amount1)
    {
        // set amount0Max and amount1Max to uint256.max to collect all fees
        // alternatively can set recipient to msg.sender
        INonfungiblePositionManager.CollectParams
            memory params = INonfungiblePositionManager.CollectParams({
                tokenId: _tokenId,
                recipient: recipient,
                // for collecting all: type(uint128).max
                amount0Max: amount0Max,
                amount1Max: amount1Max
            });

        (amount0, amount1) = _positionManager.collect(params);

        emit CollectedFees(_tokenId, amount0, amount1, msg.sender);
    }

    function resetPosition() public onlyRole(VAULT_ROLE) {
        require(_tokenId != 0, "Position not exist");
        _positionManager.burn(_tokenId);
        _tokenId = 0;
    }
}

