//SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import "./IUniswapV3Pool.sol";
import "./ISwapRouter.sol";
import "./SafeERC20.sol";
import "./Ownable.sol";
import "./INonfungiblePositionManager.sol";
import "./TickMath.sol";
import "./OracleLibrary.sol";
import "./LiquidityAmounts.sol";

// import "forge-std/console2.sol";

contract LiquidityManager is Ownable {
    using SafeERC20 for IERC20;
    using OracleLibrary for IUniswapV3Pool;
    using TickMath for int24;

    event Mint(uint256 _tokenId, uint128 _liquidity, uint256 _amount0, uint256 _amount1);
    event Refunded(address _token, uint256 _refund);
    event CollectedFees(uint256 _amount0, uint256 _amount1);
    event CollectedFeesAndAmounts(uint256 _amount0, uint256 _amount1);
    event DecreaseLiquidityAll(uint256 _amount0, uint256 _amount1, uint128 _liquidity);
    event BurnPosition(uint256 _token);
    event Swapped(uint256 _amountOut);

    error TokenExistent();
    error CannotRebalance();
    error ZeroBalance();

    //constants or setting parameters
    address public immutable token0;
    address public immutable token1;
    uint24 public immutable poolFee;
    INonfungiblePositionManager public immutable nonfungiblePositionManager;
    IUniswapV3Pool public immutable pool;
    ISwapRouter public immutable router;
    int24 public range;
    uint256 public slippage; //%
    //variables
    uint256 public tokenId;

    constructor(
        address _token0,
        address _token1,
        uint24 _poolFee,
        int24 _range,
        uint256 _slippage,
        address _positionManager,
        address _pool,
        address _router
    ) {
        token0 = _token0;
        token1 = _token1;
        poolFee = _poolFee;
        range = _range;
        slippage = _slippage;
        nonfungiblePositionManager = INonfungiblePositionManager(_positionManager);
        pool = IUniswapV3Pool(_pool);
        router = ISwapRouter(_router);
        //approve
        IERC20(token0).safeApprove(_positionManager, type(uint256).max);
        IERC20(token1).safeApprove(_positionManager, type(uint256).max);
        IERC20(token0).safeApprove(_router, type(uint256).max);
        IERC20(token1).safeApprove(_router, type(uint256).max);
    }

    /**
     * external functions
     */
    function initialMint(uint256 _amount0, uint256 _amount1)
        external
        onlyOwner
        returns (
            uint256 tokenId_,
            uint128 liquidityMinted_,
            uint256 amount0_,
            uint256 amount1_
        )
    {
        (int24 _tickLower, int24 _tickUpper) = newRange();
        return _mint(_amount0, _amount1, _tickLower, _tickUpper);
    }

    function newLiquidity(uint128 _liquidity)
        external
        onlyOwner
        returns (
            uint256 tokenId_,
            uint128 liquidityMinted_,
            uint256 amount0_,
            uint256 amount1_
        )
    {
        return _newLiquidity(_liquidity);
    }

    function _newLiquidity(uint128 _liquidity)
        internal
        returns (
            uint256 tokenId_,
            uint128 liquidityMinted_,
            uint256 amount0_,
            uint256 amount1_
        )
    {
        (uint160 sqrtRatioX96, , , , , , ) = pool.slot0();
        (int24 _tickLower, int24 _tickUpper) = newRange();
        (uint256 _amount0, uint256 _amount1) = LiquidityAmounts.getAmountsForLiquidity(
            sqrtRatioX96,
            _tickLower.getSqrtRatioAtTick(),
            _tickUpper.getSqrtRatioAtTick(),
            _liquidity
        );
        return _mint(_amount0, _amount1, _tickLower, _tickUpper);
    }

    function _mint(
        uint256 _amount0,
        uint256 _amount1,
        int24 _tickLower,
        int24 _tickUpper
    )
        internal
        returns (
            uint256 tokenId_,
            uint128 liquidity_,
            uint256 amount0_,
            uint256 amount1_
        )
    {
        if (tokenId != 0) revert TokenExistent();
        // console2.log("balanceOf", IERC20(token0).balanceOf(address(this)), IERC20(token1).balanceOf(address(this)));
        // console2.log("neededAmount", _amount0, _amount1);
        INonfungiblePositionManager.MintParams memory params = INonfungiblePositionManager.MintParams({
            token0: token0,
            token1: token1,
            fee: poolFee,
            tickLower: _tickLower,
            tickUpper: _tickUpper,
            amount0Desired: _amount0,
            amount1Desired: _amount1,
            amount0Min: (_amount0 * (100 - slippage)) / 100,
            amount1Min: (_amount1 * (100 - slippage)) / 100,
            recipient: address(this),
            deadline: block.timestamp
        });
        (tokenId_, liquidity_, amount0_, amount1_) = nonfungiblePositionManager.mint(params);
        // console2.log(tokenId_, liquidity_, amount0_, amount1_);
        emit Mint(tokenId_, liquidity_, amount0_, amount1_);

        //set tokenId
        tokenId = tokenId_;

        // Remove allowance and refund in both assets.
        if (amount0_ < _amount0) {
            // console2.log("refund0", _amount0 - amount0_);
            emit Refunded(token0, _amount0 - amount0_);
        }

        if (amount1_ < _amount1) {
            // console2.log("refund1", _amount1 - amount1_);
            emit Refunded(token1, _amount1 - amount1_);
        }
    }

    function decreaseLiquidityAll()
        external
        onlyOwner
        returns (
            uint256 amount0_,
            uint256 amount1_,
            uint128 liquidityDecreased_
        )
    {
        return _decreaseLiquidityAll();
    }

    function _decreaseLiquidityAll()
        internal
        returns (
            uint256 amount0_,
            uint256 amount1_,
            uint128 liquidityDecreased_
        )
    {
        (, , , , , , , uint128 _liquidity, , , , ) = nonfungiblePositionManager.positions(tokenId);

        INonfungiblePositionManager.DecreaseLiquidityParams memory params = INonfungiblePositionManager
            .DecreaseLiquidityParams({
                tokenId: tokenId,
                liquidity: _liquidity,
                amount0Min: 0,
                amount1Min: 0,
                deadline: block.timestamp
            });

        (amount0_, amount1_) = nonfungiblePositionManager.decreaseLiquidity(params);
        liquidityDecreased_ = _liquidity;
        emit DecreaseLiquidityAll(amount0_, amount1_, liquidityDecreased_);
    }

    function collectAllFees() external onlyOwner returns (uint256 amount0_, uint256 amount1_) {
        return _collectAllFees();
    }

    function _collectAllFees() internal returns (uint256 amount0_, uint256 amount1_) {
        INonfungiblePositionManager.CollectParams memory params = INonfungiblePositionManager.CollectParams({
            tokenId: tokenId,
            recipient: address(this),
            amount0Max: type(uint128).max,
            amount1Max: type(uint128).max
        });
        (amount0_, amount1_) = nonfungiblePositionManager.collect(params);
        emit CollectedFeesAndAmounts(amount0_, amount1_);
    }

    function burnPosition() external onlyOwner {
        _burnPosition();
    }

    function _burnPosition() internal {
        nonfungiblePositionManager.burn(tokenId);
        emit BurnPosition(tokenId);
        tokenId = 0;
    }

    function removeLiquidity() external onlyOwner returns (uint128 liquidityDecreased_) {
        return _removeLiquidity();
    }

    function _removeLiquidity() internal returns (uint128 liquidityDecreased_) {
        (uint256 _amount0Decreased, uint256 _amount1Decreased, uint128 _liquidityDecreased) = _decreaseLiquidityAll();
        (uint256 _amount0Collected, uint256 _amount1Collected) = _collectAllFees();
        if (_amount0Collected >= _amount0Decreased && _amount1Collected >= _amount1Decreased) {
            emit CollectedFees(_amount0Collected - _amount0Decreased, _amount1Collected - _amount1Decreased);
        }
        _burnPosition();
        return _liquidityDecreased;
    }

    function swapAndAddLiquidity(
        address _from,
        address _to,
        uint256 _amount,
        uint256 _amountOutMin,
        uint128 _liquidity
    ) external onlyOwner {
        _swap(_from, _to, _amount, _amountOutMin);
        _newLiquidity(_liquidity);
    }

    function withdrawRedundant(address _token, address _to) external onlyOwner {
        uint256 _tokenBalance = IERC20(_token).balanceOf(address(this));
        if (_tokenBalance == 0) revert ZeroBalance();
        IERC20(_token).safeTransfer(_to, _tokenBalance);
    }

    function withdraw(address _to) external onlyOwner {
        uint256 _balance0 = IERC20(token0).balanceOf(address(this));
        if (_balance0 > 0) IERC20(token0).safeTransfer(_to, _balance0);

        uint256 _balance1 = IERC20(token1).balanceOf(address(this));
        if (_balance1 > 0) IERC20(token1).safeTransfer(_to, _balance1);
    }

    //anyone can deposit
    function deposit(uint256 _amount0, uint256 _amount1) external {
        IERC20(token0).safeTransferFrom(msg.sender, address(this), _amount0);
        IERC20(token1).safeTransferFrom(msg.sender, address(this), _amount1);
    }

    function swap(
        address _from,
        address _to,
        uint256 _amount,
        uint256 _amountOutMin
    ) external onlyOwner {
        _swap(_from, _to, _amount, _amountOutMin);
    }

    function _swap(
        address _from,
        address _to,
        uint256 _amount,
        uint256 _amountOutMin
    ) public {
        if (_from == address(0) || _to == address(0) || _amount == 0) return;
        // console2.log(_from, _to, _amount);
        //setup for swap
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams(
            _from,
            _to,
            poolFee,
            address(this),
            block.timestamp,
            _amount,
            _amountOutMin,
            0 //sqrtPriceLimitX96
        );
        uint256 amountOut_ = router.exactInputSingle(params);
        emit Swapped(amountOut_);
        // console2.log("amountOut", amountOut_);
    }

    /**
     * setting parameters
     */
    function setRange(int24 _range) external onlyOwner {
        range = _range;
    }

    function setSlippage(uint256 _slippage) external onlyOwner {
        slippage = _slippage;
    }

    /**
     * getters
     */
    function isInRange() public view returns (bool) {
        (, int24 _tick, , , , , ) = pool.slot0();
        (, , , , , int24 tickLower, int24 tickUpper, , , , , ) = nonfungiblePositionManager.positions(tokenId);
        return (_tick >= tickLower && _tick <= tickUpper);
    }

    function newRange() public view returns (int24 tickLower_, int24 tickUpper_) {
        (, int24 _tick, , , , , ) = pool.slot0();
        int24 _SpacedBase = _tick / pool.tickSpacing();
        //round off
        if (_tick % pool.tickSpacing() > pool.tickSpacing() / 2) _SpacedBase += 1;
        tickLower_ = (_SpacedBase - range) * pool.tickSpacing();
        tickUpper_ = (_SpacedBase + range) * pool.tickSpacing();
    }

    function getAmountsForLiquidity(uint128 _liquidity) public view returns (uint256 amount0_, uint256 amount1_) {
        (uint160 sqrtRatioX96, , , , , , ) = pool.slot0();
        (int24 _tickLower, int24 _tickUpper) = newRange();
        (amount0_, amount1_) = LiquidityAmounts.getAmountsForLiquidity(
            sqrtRatioX96,
            _tickLower.getSqrtRatioAtTick(),
            _tickUpper.getSqrtRatioAtTick(),
            _liquidity
        );
        // console2.log("getAmountsForLiquidity", amount0_, amount1_);
    }

    function quoteAtTick(
        address _from,
        address _to,
        uint256 _amount
    ) public view returns (uint256 quoteAmount_) {
        (, int24 _tick, , , , , ) = pool.slot0();
        quoteAmount_ = OracleLibrary.getQuoteAtTick(_tick, uint128(_amount), _from, _to);
        // console2.log("quoteAmount", quoteAmount_);
    }

    function getRebalanceSwap(uint128 _liquidity)
        public
        view
        returns (
            address from_,
            address to_,
            uint256 amount_,
            uint256 amountOutMin_
        )
    {
        uint256 _token0Amount = IERC20(token0).balanceOf(address(this));
        uint256 _token1Amount = IERC20(token1).balanceOf(address(this));

        (uint256 _amount0, uint256 _amount1) = getAmountsForLiquidity(_liquidity);
        // console2.log("haveAmount", _token0Amount, _token1Amount);
        // console2.log("neededAmount", _amount0, _amount1);
        if (_token0Amount >= _amount0) {
            if (_token1Amount >= _amount1) {
                (from_, to_, amount_) = (address(0), address(0), 0);
            } else {
                // add buffer because needed amount change after swap
                (from_, to_, amount_) = (token0, token1, ((_token0Amount - _amount0) * 9) / 10);
                amountOutMin_ = (quoteAtTick(from_, to_, amount_) * (100 - slippage)) / 100; // estimate
            }
        } else {
            if (_token1Amount >= _amount1) {
                (from_, to_, amount_) = (token1, token0, ((_token1Amount - _amount1) * 9) / 10);
                amountOutMin_ = (quoteAtTick(from_, to_, amount_) * (100 - slippage)) / 100; // estimate
            } else {
                revert CannotRebalance();
            }
        }
    }

    function canRebalance(uint128 _liquidity) public view returns (bool) {
        uint256 _tokensOwed0 = IERC20(token0).balanceOf(address(this));
        uint256 _tokensOwed1 = IERC20(token1).balanceOf(address(this));
        (, int24 _tick, , , , , ) = pool.slot0();
        (uint256 _amount0, uint256 _amount1) = getAmountsForLiquidity(_liquidity);
        if (_tokensOwed0 >= _amount0 && _tokensOwed1 >= _amount1) {
            return true;
        } else if (_tokensOwed0 < _amount0) {
            uint256 _quoteAmount0 = OracleLibrary.getQuoteAtTick(
                _tick,
                uint128(_tokensOwed1 - _amount1),
                token1,
                token0
            );
            // console2.log("quoteAmount0", _quoteAmount0);
            if (_tokensOwed0 + _quoteAmount0 < _amount0) {
                return false;
            } else {
                return true;
            }
        } else if (_tokensOwed1 < _amount1) {
            uint256 _quoteAmount1 = OracleLibrary.getQuoteAtTick(
                _tick,
                uint128(_tokensOwed0 - _amount0),
                token0,
                token1
            );
            // console2.log("quoteAmount1", _quoteAmount1);
            if (_tokensOwed1 + _quoteAmount1 < _amount1) {
                return false;
            } else {
                return true;
            }
        } else {
            return false;
        }
    }

    function balance() external view returns (uint256, uint256) {
        return (IERC20(token0).balanceOf(address(this)), IERC20(token1).balanceOf(address(this)));
    }

    function getCurrentTick() external view returns (int24 tick_) {
        (, tick_, , , , , ) = pool.slot0();
    }

    function positions()
        external
        view
        returns (
            uint96 nonce_,
            address operator_,
            address token0_,
            address token1_,
            uint24 fee_,
            int24 tickLower_,
            int24 tickUpper_,
            uint128 liquidity_,
            uint256 feeGrowthInside0LastX128_,
            uint256 feeGrowthInside1LastX128_,
            uint128 tokensOwed0_,
            uint128 tokensOwed1_
        )
    {
        return nonfungiblePositionManager.positions(tokenId);
    }
}

