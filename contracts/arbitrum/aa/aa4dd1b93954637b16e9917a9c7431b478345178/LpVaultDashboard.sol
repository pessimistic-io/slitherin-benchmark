// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

import "./SafeMath.sol";

import "./library_Math.sol";

import "./ILpVaultDashboard.sol";
import "./ILpVault.sol";
import "./IBEP20.sol";
import "./IWhiteholePair.sol";
import "./IDashboard.sol";

contract LpVaultDashboard is ILpVaultDashboard {
    using SafeMath for uint256;

    /* ========== STATE VARIABLES ========== */

    ILpVault public lpVault;
    IWhiteholePair public GRV_USDC_LP;
    IDashboard public dashboard;
    address public GRV;

    /* ========== INITIALIZER ========== */

    constructor(
        address _lpVault,
        address _GRV_USDC_LP,
        address _GRV,
        address _dashboard
    ) public {
        lpVault = ILpVault(_lpVault);
        GRV_USDC_LP = IWhiteholePair(_GRV_USDC_LP);
        GRV = _GRV;
        dashboard = IDashboard(_dashboard);
    }

    /* ========== VIEWS ========== */

    function getLpVaultInfo(address _user) external view override returns (LpVaultData memory) {
        LpVaultData memory lpVaultData;

        (uint256 _amount, , uint256 _lastClaimTime, uint256 _pendingGrvAmount) = lpVault.userInfo(_user);
        lpVaultData.stakedLpAmount = _amount;
        lpVaultData.claimableReward = lpVault.claimableGrvAmount(_user);
        lpVaultData.pendingGrvAmount = _pendingGrvAmount;

        lpVaultData.stakedLpValueInUSD = calculateLpValueInUSD(_amount);
        lpVaultData.totalLiquidity = calculateLpValueInUSD(GRV_USDC_LP.balanceOf(address(lpVault)));
        lpVaultData.apr = calculateVaultAPR();
        lpVaultData.penaltyDuration = _lastClaimTime.add(lpVault.harvestFeePeriod());
        lpVaultData.lockDuration = _lastClaimTime.add(lpVault.lockupPeriod());

        return lpVaultData;
    }

    function calculateVaultAPR() public view returns (uint256) {
        uint256 _rewardPerInterval = lpVault.rewardPerInterval();
        uint256 _dailyRewardAmount = _rewardPerInterval.mul(86400);
        uint256 _vaultLpBalance = GRV_USDC_LP.balanceOf(address(lpVault));

        if (_vaultLpBalance == 0) {
            _vaultLpBalance = _getLpTokenUnitAmount();
        }

        uint256 _stakedValueInUSD = calculateLpValueInUSD(_vaultLpBalance);
        uint256 _grvValueInUSD = dashboard.getCurrentGRVPrice().mul(_dailyRewardAmount).div(1e18);

        if (_stakedValueInUSD == 0) {
            _stakedValueInUSD = 1e18;
        }

        uint256 _dayProfit = _grvValueInUSD.mul(1e18).div(_stakedValueInUSD);
        uint256 apr = _dayProfit.mul(365).mul(100);

        return apr;
    }

    function calculateLpValueInUSD(uint256 _amount) public view override returns (uint256) {
        uint256 _tokenBalance = 0; // USDC Balance
        address _tokenAddress = address(0);

        uint256 _pairTotalSupply = GRV_USDC_LP.totalSupply();

        if (GRV_USDC_LP.token0() == GRV) {
            _tokenAddress = GRV_USDC_LP.token1();
            _tokenBalance = IBEP20(_tokenAddress).balanceOf(address(GRV_USDC_LP));
        } else {
            _tokenAddress = GRV_USDC_LP.token0();
            _tokenBalance = IBEP20(_tokenAddress).balanceOf(address(GRV_USDC_LP));
        }

        uint256 lpValueInUSD = 0;

        if (_pairTotalSupply == 0) {
            lpValueInUSD = 0;
        } else {
            lpValueInUSD = _getAdjustedAmount(address(GRV_USDC_LP), _amount).mul(
                _getAdjustedAmount(_tokenAddress, _tokenBalance)
            ).mul(2).div(_getAdjustedAmount(address(GRV_USDC_LP), _pairTotalSupply));
        }

        return lpValueInUSD;
    }

    /* ========== PRIVATE FUNCTIONS ========== */

    function _getLpTokenUnitAmount() private view returns (uint256) {
        uint256 _token0Decimals = IBEP20(GRV_USDC_LP.token0()).decimals();
        uint256 _token0UnitAmount = 10 ** _token0Decimals;

        uint256 _token1Decimals = IBEP20(GRV_USDC_LP.token1()).decimals();
        uint256 _token1UnitAmount = 10 ** _token1Decimals;

        return Math.sqrt(_token0UnitAmount.mul(_token1UnitAmount));
    }

    function _getAdjustedAmount(address token, uint256 amount) private view returns (uint256) {
        if (token == address(0)) {
            return amount;
        } else if (keccak256(abi.encodePacked(IWhiteholePair(token).symbol())) == keccak256("Whitehole-LP")) {
            address _token0 = IWhiteholePair(token).token0();
            address _token1 = IWhiteholePair(token).token1();

            uint256 _token0Decimals = IBEP20(_token0).decimals();
            uint256 _token0UnitAmount = 10 ** _token0Decimals;

            uint256 _token1Decimals = IBEP20(_token1).decimals();
            uint256 _token1UnitAmount = 10 ** _token1Decimals;

            uint256 _lpTokenUnitAmount = Math.sqrt(_token0UnitAmount * _token1UnitAmount);
            return (amount * 1e18) / _lpTokenUnitAmount;
        } else {
            uint256 defaultDecimal = 18;
            uint256 tokenDecimal = IBEP20(token).decimals();

            if (tokenDecimal == defaultDecimal) {
                return amount;
            } else if (tokenDecimal < defaultDecimal) {
                return amount * (10**(defaultDecimal - tokenDecimal));
            } else {
                return amount / (10**(tokenDecimal - defaultDecimal));
            }
        }
    }
}


