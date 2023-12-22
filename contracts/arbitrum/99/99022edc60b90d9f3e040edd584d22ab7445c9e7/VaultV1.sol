// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import {UniswapPoolManager} from "./UniswapPoolManager.sol";
import {GelatoOps, IResolver} from "./GelatoOps.sol";

import {ERC721} from "./ERC721.sol";
import {SafeCast} from "./SafeCast.sol";
import {IERC20, SafeERC20} from "./SafeERC20.sol";
import {Ownable} from "./Ownable.sol";

import {TickMath} from "./TickMath.sol";
import {FullMath, LiquidityAmounts} from "./LiquidityAmounts.sol";

// import "forge-std/console2.sol";
// import {Ints} from "../../../test2/foundry/Ints.sol";

contract VaultV1 is UniswapPoolManager, ERC721, GelatoOps, IResolver, Ownable {
    using SafeERC20 for IERC20;
    using TickMath for int24;
    using FullMath for uint256;
    // using Ints for int24;

    /* ========== CONSTANTS ========== */
    uint256 constant MAGIC_SCALE_1E8 = 1e8; //for computing ltv
    uint16 constant MAGIC_SCALE_1E4 = 10000; //for slippage

    /* ========== STORAGES ========== */
    uint256 public tokenId = 1;
    int24 public lowerTick;
    int24 public upperTick;
    uint16 public slippageBPS;
    uint24 public tickSlippageBPS;
    uint24 public rebalanceRangeTickBPS;

    /* ========== CONSTRUCTOR ========== */
    constructor(address _pool, int24 _inputTick) ERC721("VaultV1", "VaultV1") UniswapPoolManager(_pool) {
        slippageBPS = 500;
        tickSlippageBPS = 10;
        rebalanceRangeTickBPS = 2100;

        // mint NFT
        _mint(msg.sender, tokenId); //tokenId is only 1
    }

    /* ========== VIEW FUNCTIONS ========== */
    function getPositionID() public view returns (bytes32 positionID) {
        return _getPositionID(lowerTick, upperTick);
    }

    function getUnderlyingBalances()
        external
        view
        returns (
            uint256 amount0,
            uint256 amount1,
            uint256 fees0,
            uint256 fees1,
            uint256 amount0Balance,
            uint256 amount1Balance
        )
    {
        int24 _lowerTick = lowerTick;
        int24 _upperTick = upperTick;
        (
            uint128 liquidity,
            uint256 feeGrowthInside0Last,
            uint256 feeGrowthInside1Last,
            uint128 tokensOwed0,
            uint128 tokensOwed1
        ) = pool.positions(_getPositionID(lowerTick, upperTick));

        (, int24 _tick, , , , , ) = pool.slot0();
        // compute current holdings from liquidity
        if (liquidity > 0) {
            (amount0, amount1) = LiquidityAmounts.getAmountsForLiquidity(
                _tick.getSqrtRatioAtTick(),
                _lowerTick.getSqrtRatioAtTick(),
                _upperTick.getSqrtRatioAtTick(),
                liquidity
            );
        }

        fees0 =
            _computeFeesEarned(true, feeGrowthInside0Last, liquidity, _lowerTick, _upperTick, _tick) +
            uint256(tokensOwed0);
        fees1 =
            _computeFeesEarned(false, feeGrowthInside1Last, liquidity, _lowerTick, _upperTick, _tick) +
            uint256(tokensOwed1);

        amount0Balance = token0.balanceOf(address(this));
        amount1Balance = token1.balanceOf(address(this));
    }

    function checker() external view override returns (bool canExec, bytes memory execPayload) {
        (, int24 _tick, , , , , ) = pool.slot0();
        if (_tick > upperTick || _tick < lowerTick) {
            (int24 _newLowerTick, int24 _newUpperTick) = _getNewTicks(_tick);
            execPayload = abi.encodeWithSelector(VaultV1.rebalance.selector, _newLowerTick, _newUpperTick);
            return (true, execPayload);
        } else {
            return (false, bytes("can not stoploss"));
        }
    }

    function getCurrentTick() external view returns (int24 _tick) {
        (, _tick, , , , , ) = pool.slot0();
    }

    /* ========== VIEW FUNCTIONS(INTERNAL) ========== */
    function _getNewTicks(int24 _currentTick) internal view returns (int24 _newLowerTick, int24 _newUpperTick) {
        int24 _tmpTick = _currentTick / 60;
        int24 _modTick = _currentTick % 60;
        if (_modTick > 30) {
            _tmpTick = _tmpTick + 1;
        } else if (_modTick < -30) {
            _tmpTick = _tmpTick - 1;
        }
        _tmpTick = _tmpTick * 60;
        _newLowerTick = _tmpTick - int24(rebalanceRangeTickBPS);
        _newUpperTick = _tmpTick + int24(rebalanceRangeTickBPS);
    }

    function _computeSwapAmount(
        uint256 _amount0,
        uint256 _amount1,
        uint160 _sqrtRatioX96,
        int24 _lowerTick,
        int24 _upperTick
    ) internal pure returns (bool _zeroForOne, int256 _swapAmount) {
        if (_amount0 == 0 && _amount1 == 0) return (false, 0);

        //compute swapping direction and amount
        uint128 _liquidity0 = LiquidityAmounts.getLiquidityForAmount0(
            _sqrtRatioX96,
            _upperTick.getSqrtRatioAtTick(),
            _amount0
        );
        uint128 _liquidity1 = LiquidityAmounts.getLiquidityForAmount1(
            _lowerTick.getSqrtRatioAtTick(),
            _sqrtRatioX96,
            _amount1
        );

        if (_liquidity0 > _liquidity1) {
            _zeroForOne = true;
            (uint256 _mintAmount0, ) = LiquidityAmounts.getAmountsForLiquidity(
                _sqrtRatioX96,
                _lowerTick.getSqrtRatioAtTick(),
                _upperTick.getSqrtRatioAtTick(),
                _liquidity0
            );
            uint256 _surplusAmount = _amount0 - _mintAmount0;
            //swap half of amount
            _swapAmount = SafeCast.toInt256(_surplusAmount / 2);
        } else {
            (, uint256 _mintAmount1) = LiquidityAmounts.getAmountsForLiquidity(
                _sqrtRatioX96,
                _lowerTick.getSqrtRatioAtTick(),
                _upperTick.getSqrtRatioAtTick(),
                _liquidity1
            );
            uint256 _surplusAmount = _amount1 - _mintAmount1;
            //swap half of amount
            _swapAmount = SafeCast.toInt256(_surplusAmount / 2);
        }
    }

    function _checkSlippage(uint160 _currentSqrtRatioX96, bool _zeroForOne)
        internal
        view
        returns (uint160 _swapThresholdPrice)
    {
        if (_zeroForOne) {
            return uint160(FullMath.mulDiv(_currentSqrtRatioX96, slippageBPS, MAGIC_SCALE_1E4));
        } else {
            return uint160(FullMath.mulDiv(_currentSqrtRatioX96, MAGIC_SCALE_1E4 + slippageBPS, MAGIC_SCALE_1E4));
        }
    }

    function _checkTickSlippage(int24 _inputTick, int24 _currentTick) internal view returns (bool) {
        //check _inputTick is in range of _tick.currentTick +- tickSlippageBPS
        return
            _inputTick >= _currentTick - int24(tickSlippageBPS) && _inputTick <= _currentTick + int24(tickSlippageBPS);
    }

    /* ========== EXTERNAL FUNCTIONS ========== */
    function deposit(
        uint256 _token0Amount,
        uint256 _token1Amount,
        int24 _inputTick
    ) external {
        //validation
        if (ownerOf(tokenId) != msg.sender) {
            revert("InvalidDepositSender");
        }
        if (_token0Amount == 0 || _token1Amount == 0) revert("InvalidDepositZero");

        (uint160 _sqrtRatioX96, int24 _currentTick, , , , , ) = pool.slot0();
        _checkTickSlippage(_inputTick, _currentTick);

        //set lowerTick and upperTick
        (int24 _lowerTick, int24 _upperTick) = _getNewTicks(_inputTick);
        _validateTicks(_lowerTick, _upperTick);
        lowerTick = _lowerTick;
        upperTick = _upperTick;

        // Transfer ETH and TOKEN1 from sender
        token0.safeTransferFrom(msg.sender, address(this), _token0Amount);
        token1.safeTransferFrom(msg.sender, address(this), _token1Amount);

        // Add liquidity
        _addLiquidity(_token0Amount, _token1Amount, _sqrtRatioX96, lowerTick, upperTick);
    }

    function redeem(int24 _inputTick) external {
        //validation
        if (ownerOf(tokenId) != msg.sender) {
            revert("InvalidRedeemSender");
        }

        (, int24 _currentTick, , , , , ) = pool.slot0();
        _checkTickSlippage(_inputTick, _currentTick);

        // 1. Collect fees
        // 2. Remove liquidity
        int24 _lowerTick = lowerTick;
        int24 _upperTick = upperTick;
        (uint128 _liquidity, , , , ) = pool.positions(_getPositionID(_lowerTick, _upperTick));
        if (_liquidity == 0) {
            revert("InvalidRedeemLiquidity");
        }
        _burnAndCollectFees(_lowerTick, _upperTick, _liquidity);

        // 3. Transfer
        uint256 _token0Balance = token0.balanceOf(address(this));
        uint256 _token1Balance = token1.balanceOf(address(this));
        if (_token0Balance > 0) {
            token0.safeTransfer(msg.sender, _token0Balance);
        }
        if (_token1Balance > 0) {
            token1.safeTransfer(msg.sender, _token1Balance);
        }
    }

    function rebalance(int24 _newLowerTick, int24 _newUpperTick) external onlyGelato {
        // Check tickSpacing
        _validateTicks(_newLowerTick, _newUpperTick);

        // 1. Collect fees
        // 2. Remove liquidity
        int24 _lowerTick = lowerTick;
        int24 _upperTick = upperTick;
        (uint128 liquidity, , , , ) = pool.positions(_getPositionID(_lowerTick, _upperTick));
        if (liquidity > 0) {
            _burnAndCollectFees(_lowerTick, _upperTick, liquidity);
        }

        lowerTick = _newLowerTick;
        upperTick = _newUpperTick;
        _lowerTick = _newLowerTick;
        _upperTick = _newUpperTick;
        (uint160 _sqrtRatioX96, , , , , , ) = pool.slot0();

        // 3. Compute swap amount
        uint256 _reinvest0 = token0.balanceOf(address(this));
        uint256 _reinvest1 = token1.balanceOf(address(this));
        (bool _zeroForOne, int256 _swapAmount) = _computeSwapAmount(
            _reinvest0,
            _reinvest1,
            _sqrtRatioX96,
            _lowerTick,
            _upperTick
        );

        // 4. Swap
        if (_swapAmount != 0) {
            int256 amount0Delta;
            int256 amount1Delta;
            (amount0Delta, amount1Delta) = pool.swap(
                address(this),
                _zeroForOne,
                _swapAmount,
                _checkSlippage(_sqrtRatioX96, _zeroForOne),
                ""
            );
            _reinvest0 = uint256(SafeCast.toInt256(_reinvest0) - amount0Delta);
            _reinvest1 = uint256(SafeCast.toInt256(_reinvest1) - amount1Delta);
        }

        // 5. Add liquidity
        (_sqrtRatioX96, , , , , , ) = pool.slot0();
        _addLiquidity(_reinvest0, _reinvest1, _sqrtRatioX96, _lowerTick, _upperTick);
    }

    function updateParams(
        uint16 _slippageBPS,
        uint24 _tickSlippageBPS,
        uint24 _rebalanceRangeTickBPS
    ) external onlyOwner {
        if (slippageBPS > 10000) {
            revert("InvalidslippageBPS");
        }
        if (rebalanceRangeTickBPS % 60 != 0) {
            revert("InvalidrebalanceRange");
        }
        slippageBPS = _slippageBPS;
        tickSlippageBPS = _tickSlippageBPS;
        rebalanceRangeTickBPS = _rebalanceRangeTickBPS;
    }

    /* ========== WRITE FUNCTIONS(INTERNAL) ========== */
    function _addLiquidity(
        uint256 _amount0,
        uint256 _amount1,
        uint160 _sqrtRatioX96,
        int24 _lowerTick,
        int24 _upperTick
    ) internal {
        if (_amount0 == 0 && _amount1 == 0) revert("InvalidAddLiquidityAmounts");

        uint128 liquidity_ = LiquidityAmounts.getLiquidityForAmounts(
            _sqrtRatioX96,
            lowerTick.getSqrtRatioAtTick(),
            upperTick.getSqrtRatioAtTick(),
            _amount0,
            _amount1
        );

        //mint
        if (liquidity_ > 0) {
            pool.mint(address(this), _lowerTick, _upperTick, liquidity_, "");
        }
    }

    function _burnAndCollectFees(
        int24 _lowerTick,
        int24 _upperTick,
        uint128 _liquidity
    ) internal {
        pool.burn(_lowerTick, _upperTick, _liquidity);
        pool.collect(address(this), _lowerTick, _upperTick, type(uint128).max, type(uint128).max);
    }
}

