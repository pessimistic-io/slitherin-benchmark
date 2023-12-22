// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import "./MatrixStrategyBase.sol";
import "./MatrixSwapHelperV2.sol";
import "./IUniswapV2Router02.sol";
import "./IUniswapV2Pair.sol";
import "./IMasterChef.sol";
import "./EnumerableSet.sol";

// import 'hardhat/console.sol';

/// @title Base Lp+MasterChef AutoCompound Strategy Framework,
/// all LP strategies will inherit this contract
contract MatrixLpAutoCompoundV2 is MatrixStrategyBase, MatrixSwapHelperV2 {
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    uint256 public poolId;
    address public masterchef;
    address public output;
    address public lpToken0;
    address public lpToken1;
    address public USDC = 0x04068DA6C83AFCFA0e13ba15A6696662335D5B75;
    address public unirouter;

    constructor(
        address _want,
        uint256 _poolId,
        address _masterchef,
        address _output,
        address _uniRouter,
        address _vault,
        address _treasury
    ) MatrixStrategyBase(_want, _vault, _treasury) MatrixSwapHelperV2(_uniRouter) {
        unirouter = _uniRouter;
        _initialize(_masterchef, _output, _poolId);
    }

    function _initialize(
        address _masterchef,
        address _output,
        uint256 _poolId
    ) internal virtual {
        masterchef = _masterchef;

        output = _output;
        lpToken0 = IUniswapV2Pair(want).token0();
        lpToken1 = IUniswapV2Pair(want).token1();
        poolId = _poolId;

        _setWhitelistedAddresses();
        _setDefaultSwapPaths();
        _giveAllowances();
    }

    /// @notice Get swap custom swap paths, if any
    /// @dev Otherwise reverts to default FROMTOKEN-WETH-TOTOKEN behavior
    function getSwapPath(
        address _fromToken,
        address _toToken,
        address _unirouter
    ) public view override returns (SwapPath memory _swapUniV2Path) {
        bytes32 _swapUniV2Key = keccak256(abi.encodePacked(_fromToken, _toToken, _unirouter));
        if (swapPaths[_swapUniV2Key].path.length == 0) {
            if (_fromToken != wrapped && _toToken != wrapped) {
                address[] memory _path = new address[](3);
                _path[0] = _fromToken;
                _path[1] = wrapped;
                _path[2] = _toToken;
                _swapUniV2Path.path = _path;
            } else {
                address[] memory _path = new address[](2);
                _path[0] = _fromToken;
                _path[1] = _toToken;
                _swapUniV2Path.path = _path;
            }
            _swapUniV2Path.unirouter = _unirouter;
        } else {
            return swapPaths[_swapUniV2Key];
        }
    }

    function getBestSwapPath(
        address fromToken,
        address toToken,
        uint256 amount
    ) public view returns (SwapPath memory _bestSwapPath) {
        address[] memory _routers = routers;
        uint256 _bestAmount = 0;

        for (uint256 i = 0; i < _routers.length; i++) {
            address _router = _routers[i];
            SwapPath memory _swapPath = getSwapPath(fromToken, toToken, _router);

            uint256 amountOut = _estimateSwap(_swapPath, amount);

            if (amountOut > _bestAmount) {
                _bestAmount = amountOut;
                _bestSwapPath = _swapPath;
            }

            // testing direct path if weth is not present
            if (fromToken != wrapped && toToken != wrapped) {
                SwapPath memory _swapPathDirect;

                address[] memory _path = new address[](2);
                _path[0] = fromToken;
                _path[1] = toToken;

                _swapPathDirect.path = _path;
                _swapPathDirect.unirouter = _router;

                uint256 amountOutDirect = _estimateSwap(_swapPath, amount);

                if (amountOutDirect > _bestAmount) {
                    _bestAmount = amountOutDirect;
                    _bestSwapPath = _swapPathDirect;
                }
            }
        }

        require(_bestAmount > 0, 'no-path');
        return _bestSwapPath;
    }

    /// @notice Allows strategy governor to setup custom path and dexes for token swaps
    function setSwapPath(
        address _fromToken,
        address _toToken,
        address _unirouter,
        address[] memory _path
    ) external onlyOwner {
        _setSwapPath(_fromToken, _toToken, _unirouter, _path);
    }

    /// @notice Override this to enable other routers or token swap paths
    function _setWhitelistedAddresses() internal virtual {
        whitelistedAddresses.add(USDC);
        whitelistedAddresses.add(want);
        whitelistedAddresses.add(output);
        whitelistedAddresses.add(wrapped);
        whitelistedAddresses.add(lpToken0);
        whitelistedAddresses.add(lpToken1);
    }

    function _setDefaultSwapPaths() internal virtual {}

    function _giveAllowances() internal virtual override {
        IERC20(want).safeApprove(masterchef, 0);
        IERC20(want).safeApprove(masterchef, type(uint256).max);

        IERC20(output).safeApprove(unirouter, 0);
        IERC20(output).safeApprove(unirouter, type(uint256).max);

        IERC20(lpToken0).safeApprove(unirouter, 0);
        IERC20(lpToken0).safeApprove(unirouter, type(uint256).max);

        IERC20(lpToken1).safeApprove(unirouter, 0);
        IERC20(lpToken1).safeApprove(unirouter, type(uint256).max);
    }

    function _removeAllowances() internal virtual override {
        IERC20(want).safeApprove(masterchef, 0);
        IERC20(output).safeApprove(unirouter, 0);
        IERC20(lpToken0).safeApprove(unirouter, 0);
        IERC20(lpToken1).safeApprove(unirouter, 0);
    }

    /// @dev total value managed by strategy is want + want staked in MasterChef
    function totalValue() public view virtual override returns (uint256) {
        (uint256 _totalStaked, ) = IMasterChef(masterchef).userInfo(poolId, address(this));
        return IERC20(want).balanceOf(address(this)) + _totalStaked;
    }

    function _deposit() internal virtual override {
        uint256 _wantBalance = IERC20(want).balanceOf(address(this));
        IMasterChef(masterchef).deposit(poolId, _wantBalance);
    }

    function _beforeWithdraw(uint256 _amout) internal virtual override {
        IMasterChef(masterchef).withdraw(poolId, _amout);
    }

    function _beforeHarvest() internal virtual {
        IMasterChef(masterchef).deposit(poolId, 0);
    }

    function _harvest() internal virtual override returns (uint256 _wantHarvested, uint256 _wrappedFeesAccrued) {
        _beforeHarvest();
        uint256 _outputBalance = IERC20(output).balanceOf(address(this));
        if (_outputBalance > 0) {
            if (output != wrapped) {
                SwapPath memory _swapPath = getBestSwapPath(output, wrapped, (_outputBalance * totalFee) / PERCENT_DIVISOR);
                _wrappedFeesAccrued = _swapUniV2(_swapPath, (_outputBalance * totalFee) / PERCENT_DIVISOR);
                _outputBalance = IERC20(output).balanceOf(address(this));
            } else {
                _wrappedFeesAccrued = (_outputBalance * totalFee) / PERCENT_DIVISOR;
                _outputBalance -= _wrappedFeesAccrued;
            }
            _wantHarvested = _addLiquidity(_outputBalance);

            if (lpToken0 == wrapped || lpToken1 == wrapped) {
                // Anything left here in wrapped after adding liquidity
                // Are fees accrued
                _wrappedFeesAccrued = IERC20(wrapped).balanceOf(address(this));
            }
        }
    }

    function _addLiquidity(uint256 _outputAmount) internal virtual returns (uint256 _wantHarvested) {
        uint256 _wantBalanceBefore = IERC20(want).balanceOf(address(this));
        uint256 _lpToken0BalanceBefore = IERC20(lpToken0).balanceOf(address(this));
        uint256 _lpToken1BalanceBefore = IERC20(lpToken1).balanceOf(address(this));
        if (output == lpToken0) {
            SwapPath memory _swapPath = getBestSwapPath(output, lpToken1, _outputAmount / 2);
            _swapUniV2(_swapPath, _outputAmount / 2);
        } else if (output == lpToken1) {
            SwapPath memory _swapPath = getBestSwapPath(output, lpToken0, _outputAmount / 2);
            _swapUniV2(_swapPath, _outputAmount / 2);
        } else {
            SwapPath memory _swapPathToToken0 = getBestSwapPath(output, lpToken0, _outputAmount / 2);
            SwapPath memory _swapPathToToken1 = getBestSwapPath(output, lpToken1, _outputAmount / 2);

            _swapUniV2(_swapPathToToken0, _outputAmount / 2);
            _swapUniV2(_swapPathToToken1, IERC20(output).balanceOf(address(this)));
        }

        uint256 _lp0Balance = (lpToken0 != wrapped) ? IERC20(lpToken0).balanceOf(address(this)) : IERC20(lpToken0).balanceOf(address(this)) - _lpToken0BalanceBefore;
        uint256 _lp1Balance = (lpToken1 != wrapped) ? IERC20(lpToken1).balanceOf(address(this)) : IERC20(lpToken1).balanceOf(address(this)) - _lpToken1BalanceBefore;

        IUniswapV2Router02(unirouter).addLiquidity(lpToken0, lpToken1, _lp0Balance, _lp1Balance, 1, 1, address(this), block.timestamp);
        return IERC20(want).balanceOf(address(this)) - _wantBalanceBefore;
    }

    function _beforePanic() internal virtual override {
        IMasterChef(masterchef).emergencyWithdraw(poolId);
    }

    /// @dev _beforeRetireStrat behaves exactly like _beforePanic hook
    function _beforeRetireStrat() internal override {
        _beforePanic();
    }
}

