// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import "./MatrixStrategyBase.sol";
import "./MatrixSwapHelper.sol";
import "./IUniswapV2Router02.sol";
import "./IUniswapV2Pair.sol";
import "./IMasterChef.sol";
import "./EnumerableSet.sol";

/// @title Base Lp+MasterChef AutoCompound Strategy Framework,
/// all LP strategies will inherit this contract
contract MatrixLpAutoCompound is MatrixStrategyBase, MatrixSwapHelper {
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    uint256 public poolId;
    address public masterchef;
    address public output;
    address public lpToken0;
    address public lpToken1;
    address public USDC = 0x04068DA6C83AFCFA0e13ba15A6696662335D5B75;

    constructor(
        address _want,
        uint256 _poolId,
        address _masterchef,
        address _output,
        address _uniRouter,
        address _vault,
        address _treasury
    )
        MatrixStrategyBase(_want, _vault, _treasury)
        MatrixSwapHelper(_uniRouter)
    {
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
        whitelistedAddresses.add(unirouter);
        whitelistedAddresses.add(USDC);
        whitelistedAddresses.add(want);
        whitelistedAddresses.add(output);
        whitelistedAddresses.add(wrapped);
        whitelistedAddresses.add(lpToken0);
        whitelistedAddresses.add(lpToken1);
    }

    function _setDefaultSwapPaths() internal virtual {
        // Default output to lp0 paths
        if (lpToken0 == wrapped) {
            address[] memory _path = new address[](2);
            _path[0] = output;
            _path[1] = wrapped;
            _setSwapPath(output, lpToken0, address(0), _path);
        } else if (lpToken0 != output) {
            address[] memory _path = new address[](3);
            _path[0] = output;
            _path[1] = wrapped;
            _path[2] = lpToken0;
            _setSwapPath(output, lpToken0, address(0), _path);
        }

        // Default output to lp1 paths
        if (lpToken1 == wrapped) {
            address[] memory _path = new address[](2);
            _path[0] = output;
            _path[1] = wrapped;
            _setSwapPath(output, lpToken1, address(0), _path);
        } else if (lpToken1 != output) {
            address[] memory _path = new address[](3);
            _path[0] = output;
            _path[1] = wrapped;
            _path[2] = lpToken1;
            _setSwapPath(output, lpToken1, address(0), _path);
        }

        if (output != wrapped) {
            address[] memory _path = new address[](2);
            _path[0] = output;
            _path[1] = wrapped;
            _setSwapPath(output, wrapped, address(0), _path);
        }
    }

    function _giveAllowances() internal override {
        IERC20(want).safeApprove(masterchef, 0);
        IERC20(want).safeApprove(masterchef, type(uint256).max);

        IERC20(output).safeApprove(unirouter, 0);
        IERC20(output).safeApprove(unirouter, type(uint256).max);

        IERC20(lpToken0).safeApprove(unirouter, 0);
        IERC20(lpToken0).safeApprove(unirouter, type(uint256).max);

        IERC20(lpToken1).safeApprove(unirouter, 0);
        IERC20(lpToken1).safeApprove(unirouter, type(uint256).max);
    }

    function _removeAllowances() internal override {
        IERC20(want).safeApprove(masterchef, 0);
        IERC20(output).safeApprove(unirouter, 0);
        IERC20(lpToken0).safeApprove(unirouter, 0);
        IERC20(lpToken1).safeApprove(unirouter, 0);
    }

    /// @dev total value managed by strategy is want + want staked in MasterChef
    function totalValue() public view virtual override returns (uint256) {
        (uint256 _totalStaked, ) = IMasterChef(masterchef).userInfo(
            poolId,
            address(this)
        );
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

    function _harvest()
        internal
        virtual
        override
        returns (uint256 _wantHarvested, uint256 _wrappedFeesAccrued)
    {
        _beforeHarvest();
        uint256 _outputBalance = IERC20(output).balanceOf(address(this));
        if (_outputBalance > 0) {
            if (output != wrapped) {
                _wrappedFeesAccrued = _swap(
                    output,
                    wrapped,
                    (_outputBalance * totalFee) / PERCENT_DIVISOR
                );
                _outputBalance = IERC20(output).balanceOf(address(this));
            } else {
                _wrappedFeesAccrued =
                    (_outputBalance * totalFee) /
                    PERCENT_DIVISOR;
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

    function _addLiquidity(uint256 _outputAmount)
        internal
        virtual
        returns (uint256 _wantHarvested)
    {
        uint256 _wantBalanceBefore = IERC20(want).balanceOf(address(this));
        uint256 _lpToken0BalanceBefore = IERC20(lpToken0).balanceOf(
            address(this)
        );
        uint256 _lpToken1BalanceBefore = IERC20(lpToken1).balanceOf(
            address(this)
        );
        if (output == lpToken0) {
            _swap(output, lpToken1, _outputAmount / 2);
        } else if (output == lpToken1) {
            _swap(output, lpToken0, _outputAmount / 2);
        } else {
            _swap(output, lpToken0, _outputAmount / 2);
            _swap(output, lpToken1, IERC20(output).balanceOf(address(this)));
        }

        uint256 _lp0Balance = (lpToken0 != wrapped)
            ? IERC20(lpToken0).balanceOf(address(this))
            : IERC20(lpToken0).balanceOf(address(this)) -
                _lpToken0BalanceBefore;
        uint256 _lp1Balance = (lpToken1 != wrapped)
            ? IERC20(lpToken1).balanceOf(address(this))
            : IERC20(lpToken1).balanceOf(address(this)) -
                _lpToken1BalanceBefore;

        IUniswapV2Router02(unirouter).addLiquidity(
            lpToken0,
            lpToken1,
            _lp0Balance,
            _lp1Balance,
            1,
            1,
            address(this),
            block.timestamp
        );
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

