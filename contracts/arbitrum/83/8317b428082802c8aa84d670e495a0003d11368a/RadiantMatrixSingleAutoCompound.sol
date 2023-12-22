// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import "./MatrixStrategyBase.sol";
import "./MatrixSwapHelper.sol";
import "./IUniswapV2Router02.sol";
import "./IUniswapV2Pair.sol";
import "./IMultiFeeDistribution.sol";
import "./rToken.sol";
import "./rPool.sol";
import "./EnumerableSet.sol";
//import "hardhat/console.sol";

/// @title Radiant Single Staking autocompounder strategy
contract RadiantMatrixSingleAutoCompound is
    MatrixStrategyBase,
    MatrixSwapHelper
{
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    uint256 public poolId;
    address public masterchef;
    address public output;
    address public USDC = 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8;
    uint256 public rewardsLength = 6;

    uint256 public lastTotalValue;
    uint256 public lastHarvestTime;
    uint256 public rewardApr;

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
        lastHarvestTime = block.timestamp;
    }

    function _initialize(
        address _masterchef,
        address _output,
        uint256 _poolId
    ) internal virtual {
        masterchef = _masterchef;
        output = _output;
        poolId = _poolId;
        wrapped = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
        treasury = 0xEaD9f532C72CF35dAb18A42223eE7A1B19bC5aBF;

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

        for (uint256 i = 1; i < rewardsLength; i++) {
            address _rToken = IMultiFeeDistribution(masterchef).rewardTokens(i);
            address _underlying = rToken(_rToken).UNDERLYING_ASSET_ADDRESS();
            whitelistedAddresses.add(_underlying);
        }
    }

    function _setDefaultSwapPaths() internal virtual {
        for (uint256 i = 0; i < rewardsLength; i++) {
            address _token = IMultiFeeDistribution(masterchef).rewardTokens(i);
            if (i > 0) {
                address _underlying = rToken(_token).UNDERLYING_ASSET_ADDRESS();
                _token = _underlying;
            }
            if (_token == wrapped) {
                address[] memory _path = new address[](2);
                _path[0] = _token;
                _path[1] = output;
                _setSwapPath(_token, output, unirouter, _path);
            } else if (_token != output) {
                address[] memory _path = new address[](3);
                _path[0] = _token;
                _path[1] = wrapped;
                _path[2] = output;
                _setSwapPath(_token, output, unirouter, _path);
            }
        }

        address[] memory _path = new address[](2);
        _path[0] = output;
        _path[1] = wrapped;
        _setSwapPath(output, wrapped, unirouter, _path);
    }

    function _giveAllowances() internal override {
        IERC20(want).safeApprove(masterchef, 0);
        IERC20(want).safeApprove(masterchef, type(uint256).max);
    }

    function _removeAllowances() internal override {
        IERC20(want).safeApprove(masterchef, 0);
    }

    /// @dev total value managed by strategy is want + want staked in MasterChef
    function totalValue() public view virtual override returns (uint256) {
        return IERC20(want).balanceOf(address(this)) + _getStakedValue();
    }

    function setRewardsLength(uint256 _rewardsLength) external onlyOwner {
        require(_rewardsLength > 0, "invalid-rewards-length");
        rewardsLength = _rewardsLength;
        _setWhitelistedAddresses();
        _setDefaultSwapPaths();
    }

    function withdrawable() public view virtual returns (uint256 _unlocked) {
        (, _unlocked, , ) = IMultiFeeDistribution(masterchef).lockedBalances(
            address(this)
        );
    }

    function _getStakedValue() internal view returns (uint256 _total) {
        (_total, , , ) = IMultiFeeDistribution(masterchef).lockedBalances(
            address(this)
        );
    }

    function _deposit() internal virtual override {
        uint256 _rdntBalance = IERC20(want).balanceOf(address(this));
        if (_rdntBalance > 0)
            IMultiFeeDistribution(masterchef).stake(
                _rdntBalance,
                true,
                address(this)
            );
    }

    function _beforeWithdraw(uint256 _amount) internal virtual override {
        require(_amount <= withdrawable(), "not-enough-withdrawable-balance");
        IMultiFeeDistribution(masterchef).withdrawExpiredLocks();
    }

    function _beforeHarvest() internal virtual {}

    function _harvest()
        internal
        virtual
        override
        returns (uint256 _wantHarvested, uint256 _wrappedFeesAccrued)
    {
        _beforeHarvest();
        lastTotalValue = totalValue();
        uint256 _rdntBalanceBefore = IERC20(output).balanceOf(address(this));
        address[] memory _rewardTokens = new address[](rewardsLength);
        for (uint256 i = 0; i < rewardsLength; i++) {
            _rewardTokens[i] = IMultiFeeDistribution(masterchef).rewardTokens(
                i
            );
        }
        IMultiFeeDistribution(masterchef).getReward(_rewardTokens);

        for (uint256 i = 0; i < rewardsLength; i++) {
            address _token = _rewardTokens[i];
            if (i > 0) {
                address _underlying = rToken(_rewardTokens[i])
                    .UNDERLYING_ASSET_ADDRESS();
                address _pool = rToken(_rewardTokens[i]).POOL();
                if (IERC20(_rewardTokens[i]).balanceOf(address(this)) > 0) {
                    rPool(_pool).withdraw(
                        _underlying,
                        0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff,
                        address(this)
                    );
                    _token = _underlying;
                } else {
                    continue;
                }
            }
            _swap(_token, output, IERC20(_token).balanceOf(address(this)));
        }

        uint256 _outputBalance = IERC20(output).balanceOf(address(this)) -
            _rdntBalanceBefore;

        uint256 _elapsedFromLastHarvest = block.timestamp - lastHarvestTime;
        uint256 _rewardPerSecond = (_outputBalance * 1e18) /
            _elapsedFromLastHarvest;
        uint256 _rewardPerDay = _rewardPerSecond * 86400;
        rewardApr = (_rewardPerDay * 365) / lastTotalValue;
        lastHarvestTime = block.timestamp;

        if (_outputBalance > 0) {
            _wrappedFeesAccrued = _swap(
                output,
                wrapped,
                (_outputBalance * totalFee) / PERCENT_DIVISOR
            );
            _wantHarvested =
                IERC20(output).balanceOf(address(this)) -
                _rdntBalanceBefore;
        }
    }

    function _beforePanic() internal virtual override {
        uint256 _staked = _getStakedValue();
        IMultiFeeDistribution(masterchef).withdrawExpiredLocks();
        require(
            IERC20(want).balanceOf(address(this)) >= _staked,
            "panic-failed"
        );
    }

    /// @dev _beforeRetireStrat behaves exactly like _beforePanic hook
    function _beforeRetireStrat() internal override {
        _beforePanic();
    }
}

