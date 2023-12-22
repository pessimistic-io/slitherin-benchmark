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

    error CannotRebalance();
    error ZeroBalance();

    //constants or setting parameters
    address public immutable token0;
    address public immutable token1;
    uint24 public immutable poolFee;
    INonfungiblePositionManager public immutable nonfungiblePositionManager;
    IUniswapV3Pool public immutable pool;
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
        address _pool
    ) {
        token0 = _token0;
        token1 = _token1;
        poolFee = _poolFee;
        range = _range;
        slippage = _slippage;
        nonfungiblePositionManager = INonfungiblePositionManager(_positionManager);
        pool = IUniswapV3Pool(_pool);
        //approve
        IERC20(token0).safeApprove(_positionManager, type(uint256).max);
        IERC20(token1).safeApprove(_positionManager, type(uint256).max);
        IERC20(token0).safeApprove(_pool, type(uint256).max);
        IERC20(token1).safeApprove(_pool, type(uint256).max);
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
        // console2.log("newLiquidity", _amount0, _amount1);
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
        IERC20(token0).safeTransferFrom(msg.sender, address(this), _amount0);
        IERC20(token1).safeTransferFrom(msg.sender, address(this), _amount1);

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
        emit Mint(tokenId_, liquidity_, amount0_, amount1_);

        //set tokenId
        tokenId = tokenId_;

        // Remove allowance and refund in both assets.
        if (amount0_ < _amount0) {
            uint256 _refund0 = _amount0 - amount0_;
            // console2.log("refund0", _refund0);
            IERC20(token0).safeTransfer(msg.sender, _refund0);
            emit Refunded(token0, _refund0);
        }

        if (amount1_ < _amount1) {
            uint256 _refund1 = _amount1 - amount1_;
            // console2.log("refund1", _refund1);
            IERC20(token1).safeTransfer(msg.sender, _refund1);
            emit Refunded(token1, _refund1);
        }
    }

    function increaseLiquidity(uint256 _amount0, uint256 _amount1)
        external
        onlyOwner
        returns (
            uint128 liquidity_,
            uint256 amount0_,
            uint256 amount1_
        )
    {
        IERC20(token0).safeTransferFrom(msg.sender, address(this), _amount0);
        IERC20(token1).safeTransferFrom(msg.sender, address(this), _amount1);

        INonfungiblePositionManager.IncreaseLiquidityParams memory params = INonfungiblePositionManager
            .IncreaseLiquidityParams({
                tokenId: tokenId,
                amount0Desired: _amount0,
                amount1Desired: _amount1,
                amount0Min: 0,
                amount1Min: 0,
                deadline: block.timestamp
            });

        (liquidity_, amount0_, amount1_) = nonfungiblePositionManager.increaseLiquidity(params);
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

        _sendToOwner(amount0_, amount1_);
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

    function renewPosition(
        address _from,
        address _to,
        uint256 _amount
    )
        external
        onlyOwner
        returns (
            uint256 tokenId_,
            uint128 liquidity_,
            uint256 amount0_,
            uint256 amount1_
        )
    {
        uint128 _liquidity = _removeLiquidity();
        _swap(_from, _to, _amount);
        return _newLiquidity(_liquidity);
    }

    function _swap(
        address _from,
        address _to,
        uint256 _amount
    ) internal {
        if (_from == address(0) || _to == address(0) || _amount == 0) return;
        uint256 _amountOutMinimum = (_amount * (100 - slippage)) / 100;
        //setup for swap
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams(
            _from,
            _to,
            3000, //fee
            address(this),
            block.timestamp,
            _amount,
            _amountOutMinimum,
            0 //sqrtPriceLimitX96
        );

        uint256 amountOut_ = ISwapRouter(address(pool)).exactInputSingle(params);
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

    function getRebalanceAmounts() public view returns (uint256 amount0_, uint256 amount1_) {
        (uint160 sqrtRatioX96, , , , , , ) = pool.slot0();
        (int24 _tickLower, int24 _tickUpper) = newRange();
        (, , , , , , , uint128 _liquidity, , , , ) = nonfungiblePositionManager.positions(tokenId);
        (amount0_, amount1_) = LiquidityAmounts.getAmountsForLiquidity(
            sqrtRatioX96,
            _tickLower.getSqrtRatioAtTick(),
            _tickUpper.getSqrtRatioAtTick(),
            _liquidity
        );
    }

    function canRebalance() public view returns (bool) {
        (, int24 _tick, , , , , ) = pool.slot0();
        (uint256 _amount0, uint256 _amount1) = getRebalanceAmounts();
        uint256 _amount0Own = IERC20(token0).balanceOf(msg.sender);
        uint256 _amount1Own = IERC20(token1).balanceOf(msg.sender);

        if (_amount0Own >= _amount0 && _amount1Own >= _amount1) {
            return true;
        } else if (_amount0Own < _amount0) {
            uint256 _quoteAmount0 = OracleLibrary.getQuoteAtTick(
                _tick,
                uint128(_amount1Own - _amount1),
                token1,
                token0
            );
            // console2.log("quoteAmount0", _quoteAmount0);
            if (_amount0Own + _quoteAmount0 < _amount0) {
                return false;
            } else {
                return true;
            }
        } else if (_amount1Own < _amount1) {
            uint256 _quoteAmount1 = OracleLibrary.getQuoteAtTick(
                _tick,
                uint128(_amount0Own - _amount0),
                token0,
                token1
            );
            // console2.log("quoteAmount1", _quoteAmount1);
            if (_amount1Own + _quoteAmount1 < _amount1) {
                return false;
            } else {
                return true;
            }
        } else {
            return false;
        }
    }

    function getRebalanceSwap()
        external
        view
        returns (
            address from_,
            address to_,
            uint256 amount_
        )
    {
        (uint256 _amount0, uint256 _amount1) = getRebalanceAmounts();
        uint256 _amount0Own = IERC20(token0).balanceOf(msg.sender);
        uint256 _amount1Own = IERC20(token1).balanceOf(msg.sender);
        if (_amount0Own >= _amount0 && _amount1Own >= _amount1) {
            (from_, to_, amount_) = (address(0), address(0), 0);
        } else if (_amount0Own < _amount0) {
            (from_, to_, amount_) = (token1, token0, _amount1Own - _amount1);
        } else if (_amount1Own < _amount1) {
            (from_, to_, amount_) = (token0, token1, _amount0Own - _amount0);
        } else {
            revert CannotRebalance();
        }
    }

    function withdrawRedundant(address _token) external onlyOwner {
        uint256 _tokenBalance = IERC20(_token).balanceOf(address(this));
        if (_tokenBalance == 0) revert ZeroBalance();
        IERC20(_token).safeTransfer(msg.sender, _tokenBalance);
    }

    /**
     * internal functions
     */
    function _sendToOwner(uint256 _amount0, uint256 _amount1) internal {
        IERC20(token0).safeTransfer(owner(), _amount0);
        IERC20(token1).safeTransfer(owner(), _amount1);
    }
}

