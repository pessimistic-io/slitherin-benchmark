// SPDX-License-Identifier: Unlicense

pragma solidity >=0.7.3;

import "./Math.sol";
import "./SafeMath.sol";
import "./SignedSafeMath.sol";
import "./IERC20.sol";
import "./SafeERC20.sol";
import "./ReentrancyGuard.sol";

import "./IUniswapV3MintCallback.sol";
import "./IUniswapV3SwapCallback.sol";
import "./IUniswapV3Pool.sol";
import "./TickMath.sol";
import "./FullMath.sol";
import "./LiquidityAmounts.sol";

contract UniV3LpMaker is
    IUniswapV3MintCallback,
    IUniswapV3SwapCallback,
    ReentrancyGuard
{
    using SafeERC20 for IERC20;
    using SafeMath for uint256;
    using SignedSafeMath for int256;

    IUniswapV3Pool public pool;
    IERC20 public token0;
    IERC20 public token1;
    int24 public tickSpacing;

    int24 public t1;
    int24 public t2;
    int24 public t3;
    int24 public t4;

    address public owner;
    address public operator;

    event CollectFees(
        uint256 totalAmount0,
        uint256 totalAmount1,
        uint256 feeAmount0,
        uint256 feeAmount1
    );
    event Mint(
        int24 tickLower,
        int24 tickUpper,
        uint256 amount0,
        uint256 amount1
    );

    constructor(
        address _pool,
        address _owner,
        address _operator
    ) {
        require(_pool != address(0));
        require(_owner != address(0));
        pool = IUniswapV3Pool(_pool);
        token0 = IERC20(pool.token0());
        token1 = IERC20(pool.token1());
        require(address(token0) != address(0));
        require(address(token1) != address(0));
        tickSpacing = pool.tickSpacing();

        owner = _owner;
        operator = _operator;
    }

    function rebalance(
        int24 _t1,
        int24 _t2,
        int24 _t3,
        int24 _t4
    ) external nonReentrant onlyOperator {
        require(_t1 < _t2 && _t1 % tickSpacing == 0 && _t2 % tickSpacing == 0);
        require(_t3 < _t4 && _t3 % tickSpacing == 0 && _t4 % tickSpacing == 0);
        require(_t4 != _t2 || _t3 != _t1);

        /// Withdraw all liquidity and collect all fees from Uniswap pool
        (uint128 t12Liquidtidy, , ) = _position(t1, t2);
        _burnAndCollect(t1, t2, t12Liquidtidy, address(this), true, 0, 0);
        (uint128 t34Liquidtidy, , ) = _position(t3, t4);
        _burnAndCollect(t3, t4, t34Liquidtidy, address(this), true, 0, 0);
        uint256 amount0 = token0.balanceOf(address(this));
        uint256 amount1 = token1.balanceOf(address(this));

        t1 = _t1;
        t2 = _t2;
        t12Liquidtidy = _liquidityForAmounts(t1, t2, amount0, amount1);
        _mintLiquidity(t1, t2, t12Liquidtidy, address(this), 0, 0);

        amount0 = token0.balanceOf(address(this));
        amount1 = token1.balanceOf(address(this));
        t3 = _t3;
        t4 = _t4;
        t34Liquidtidy = _liquidityForAmounts(t3, t4, amount0, amount1);
        _mintLiquidity(t3, t4, t34Liquidtidy, address(this), 0, 0);
    }

    function followTrending(int24 _tickLower, int24 _tickUpper)
        external
        nonReentrant
        onlyOperator
    {
        require(
            _tickLower < _tickUpper &&
                _tickLower % tickSpacing == 0 &&
                _tickUpper % tickSpacing == 0
        );

        if (_tickLower >= t4) {
            //ticker上涨情况
            (uint128 t12Liquidtidy, , ) = _position(t1, t2);
            _burnAndCollect(t1, t2, t12Liquidtidy, address(this), true, 0, 0);
            //sellToken1
            bool zeroToOne = false;

            pool.swap(
                address(this),
                zeroToOne,
                int256(token1.balanceOf(address(this))),
                zeroToOne
                    ? TickMath.MIN_SQRT_RATIO + 1
                    : TickMath.MAX_SQRT_RATIO - 1,
                ""
            );
            t1 = t3;
            t2 = t4;
            t3 = _tickLower;
            t4 = _tickUpper;
            uint128 t34Liquidtidy = _liquidityForAmounts(
                t3,
                t4,
                token0.balanceOf(address(this)),
                token1.balanceOf(address(this))
            );
            _mintLiquidity(t3, t4, t34Liquidtidy, address(this), 0, 0);
        } else if (_tickUpper <= t1) {
            //下跌情况
            (uint128 t34Liquidtidy, , ) = _position(t3, t4);

            _burnAndCollect(t3, t4, t34Liquidtidy, address(this), true, 0, 0);
            //sellToken0
            bool zeroToOne = true;
            pool.swap(
                address(this),
                zeroToOne,
                int256(token0.balanceOf(address(this))),
                zeroToOne
                    ? TickMath.MIN_SQRT_RATIO + 1
                    : TickMath.MAX_SQRT_RATIO - 1,
                ""
            );
            t3 = t1;
            t4 = t2;

            t1 = _tickLower;
            t2 = _tickUpper;
            uint128 t12Liquidtidy = _liquidityForAmounts(
                t1,
                t2,
                token0.balanceOf(address(this)),
                token1.balanceOf(address(this))
            );
            _mintLiquidity(t1, t2, t12Liquidtidy, address(this), 0, 0);
        }
    }

    function compound() external nonReentrant onlyOperator {
        // collect fees for compounding
        _zeroBurn(t1, t2);
        _zeroBurn(t3, t4);

        uint128 liquidity = _liquidityForAmounts(
            t1,
            t2,
            token0.balanceOf(address(this)),
            token1.balanceOf(address(this))
        );
        _mintLiquidity(t1, t2, liquidity, address(this), 0, 0);

        liquidity = _liquidityForAmounts(
            t3,
            t4,
            token0.balanceOf(address(this)),
            token1.balanceOf(address(this))
        );
        _mintLiquidity(t3, t4, liquidity, address(this), 0, 0);
    }

    function _zeroBurn(int24 tickLower, int24 tickUpper)
        internal
        returns (uint128 liquidity)
    {
        /// update fees for inclusion
        (liquidity, , ) = _position(tickLower, tickUpper);
        if (liquidity > 0) {
            pool.burn(tickLower, tickUpper, 0);
            pool.collect(
                address(this),
                tickLower,
                tickUpper,
                type(uint128).max,
                type(uint128).max
            );
        }
    }

    function _mintLiquidity(
        int24 tickLower,
        int24 tickUpper,
        uint128 liquidity,
        address payer,
        uint256 amount0Min,
        uint256 amount1Min
    ) internal {
        if (liquidity > 0) {
            (uint256 amount0, uint256 amount1) = pool.mint(
                address(this),
                tickLower,
                tickUpper,
                liquidity,
                abi.encode(payer)
            );
            require(amount0 >= amount0Min && amount1 >= amount1Min, "PSC");
            emit Mint(tickLower, tickUpper, amount0, amount1);
        }
    }

    function _burnAndCollect(
        int24 tickLower,
        int24 tickUpper,
        uint128 liquidity,
        address to,
        bool collectAll,
        uint256 amount0Min,
        uint256 amount1Min
    ) internal returns (uint256 amount0, uint256 amount1) {
        if (liquidity > 0) {
            /// Burn liquidity
            (uint256 owed0, uint256 owed1) = pool.burn(
                tickLower,
                tickUpper,
                liquidity
            );
            require(owed0 >= amount0Min && owed1 >= amount1Min, "PSC");

            // Collect amount owed
            uint128 collect0 = collectAll
                ? type(uint128).max
                : _uint128Safe(owed0);
            uint128 collect1 = collectAll
                ? type(uint128).max
                : _uint128Safe(owed1);
            if (collect0 > 0 || collect1 > 0) {
                (amount0, amount1) = pool.collect(
                    to,
                    tickLower,
                    tickUpper,
                    collect0,
                    collect1
                );
                emit CollectFees(
                    owed0,
                    owed1,
                    amount0.sub(owed0),
                    amount1.sub(owed1)
                );
            }
        }
    }

    function _position(int24 tickLower, int24 tickUpper)
        internal
        view
        returns (
            uint128 liquidity,
            uint128 tokensOwed0,
            uint128 tokensOwed1
        )
    {
        bytes32 positionKey = keccak256(
            abi.encodePacked(address(this), tickLower, tickUpper)
        );
        (liquidity, , , tokensOwed0, tokensOwed1) = pool.positions(positionKey);
    }

    function _amountsForLiquidity(
        int24 tickLower,
        int24 tickUpper,
        uint128 liquidity
    ) internal view returns (uint256, uint256) {
        (uint160 sqrtRatioX96, , , , , , ) = pool.slot0();
        return
            LiquidityAmounts.getAmountsForLiquidity(
                sqrtRatioX96,
                TickMath.getSqrtRatioAtTick(tickLower),
                TickMath.getSqrtRatioAtTick(tickUpper),
                liquidity
            );
    }

    function _liquidityForAmounts(
        int24 tickLower,
        int24 tickUpper,
        uint256 amount0,
        uint256 amount1
    ) internal view returns (uint128) {
        (uint160 sqrtRatioX96, , , , , , ) = pool.slot0();
        return
            LiquidityAmounts.getLiquidityForAmounts(
                sqrtRatioX96,
                TickMath.getSqrtRatioAtTick(tickLower),
                TickMath.getSqrtRatioAtTick(tickUpper),
                amount0,
                amount1
            );
    }

    function _uint128Safe(uint256 x) internal pure returns (uint128) {
        assert(x <= type(uint128).max);
        return uint128(x);
    }

    function uniswapV3MintCallback(
        uint256 amount0,
        uint256 amount1,
        bytes calldata data
    ) external override {
        require(msg.sender == address(pool));
        if (amount0 > 0) token0.safeTransfer(msg.sender, amount0);
        if (amount1 > 0) token1.safeTransfer(msg.sender, amount1);
    }

    function uniswapV3SwapCallback(
        int256 amount0Delta,
        int256 amount1Delta,
        bytes calldata data
    ) external override {
        require(msg.sender == address(pool));
        if (amount0Delta > 0)
            token0.safeTransfer(msg.sender, uint256(amount0Delta));
        if (amount1Delta > 0)
            token1.safeTransfer(msg.sender, uint256(amount1Delta));
    }

    function getTotalAmounts()
        public
        view
        returns (uint256 total0, uint256 total1)
    {
        (, uint256 buy0, uint256 buy1) = getBuyPosition();
        (, uint256 sell0, uint256 sell1) = getSellPosition();
        total0 = token0.balanceOf(address(this)).add(buy0).add(sell0);
        total1 = token1.balanceOf(address(this)).add(buy1).add(sell1);
    }

    function getBuyPosition()
        public
        view
        returns (
            uint128 liquidity,
            uint256 amount0,
            uint256 amount1
        )
    {
        (
            uint128 positionLiquidity,
            uint128 tokensOwed0,
            uint128 tokensOwed1
        ) = _position(t1, t2);
        (amount0, amount1) = _amountsForLiquidity(t1, t2, positionLiquidity);
        amount0 = amount0.add(uint256(tokensOwed0));
        amount1 = amount1.add(uint256(tokensOwed1));
        liquidity = positionLiquidity;
    }

    function getSellPosition()
        public
        view
        returns (
            uint128 liquidity,
            uint256 amount0,
            uint256 amount1
        )
    {
        (
            uint128 positionLiquidity,
            uint128 tokensOwed0,
            uint128 tokensOwed1
        ) = _position(t3, t4);
        (amount0, amount1) = _amountsForLiquidity(t3, t4, positionLiquidity);
        amount0 = amount0.add(uint256(tokensOwed0));
        amount1 = amount1.add(uint256(tokensOwed1));
        liquidity = positionLiquidity;
    }

    function currentTick() public view returns (int24 tick) {
        (, tick, , , , , ) = pool.slot0();
    }

    function withdrawToken(
        IERC20 token,
        uint256 amount,
        address to
    ) external onlyOwner {
        token.safeTransfer(to, amount);
    }

    function emergencyBurn() external onlyOwner {
        (uint128 t12Liquidtidy, , ) = _position(t1, t2);
        _burnAndCollect(t1, t2, t12Liquidtidy, address(this), true, 0, 0);

        (uint128 t34Liquidtidy, , ) = _position(t3, t4);

        _burnAndCollect(t3, t4, t34Liquidtidy, address(this), true, 0, 0);
    }

    function withdraw() external onlyOwner {
        (uint128 t12Liquidtidy, , ) = _position(t1, t2);
        _burnAndCollect(t1, t2, t12Liquidtidy, address(this), true, 0, 0);

        (uint128 t34Liquidtidy, , ) = _position(t3, t4);

        _burnAndCollect(t3, t4, t34Liquidtidy, address(this), true, 0, 0);

        uint256 amount0 = token0.balanceOf(address(this));
        uint256 amount1 = token1.balanceOf(address(this));
        if (amount0 > 0) token0.safeTransfer(owner, amount0);
        if (amount1 > 0) token1.safeTransfer(owner, amount1);
    }

    function setOperator(address _operator) external onlyOwner {
        operator = _operator;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "only owner");
        _;
    }
    modifier onlyOperator() {
        require(msg.sender == operator, "only operator");
        _;
    }
}

