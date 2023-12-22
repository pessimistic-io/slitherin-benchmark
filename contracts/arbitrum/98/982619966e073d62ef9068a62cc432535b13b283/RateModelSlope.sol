// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.6.12;

import "./Math.sol";
import "./SafeMath.sol";
import "./OwnableUpgradeable.sol";
import "./IRateModel.sol";

/// @dev https://bscscan.com/address/0x9535c1f26df97451671913f7aeda646c0f1eda85#readProxyContract
contract RateModelSlope is IRateModel, OwnableUpgradeable {
    using SafeMath for uint256;

    uint256 private baseRatePerYear;
    uint256 private slopePerYearFirst;
    uint256 private slopePerYearSecond;
    uint256 private optimal;

    /// @notice Contract 초기화 변수 설정
    /// @param _baseRatePerYear 기본 이자율
    /// @param _slopePerYearFirst optimal 이전 이자 계수
    /// @param _slopePerYearSecond optimal 초과 이자 계수
    /// @param _optimal double-slope optimal
    function initialize(
        uint256 _baseRatePerYear,
        uint256 _slopePerYearFirst,
        uint256 _slopePerYearSecond,
        uint256 _optimal
    ) external initializer {
        __Ownable_init();

        baseRatePerYear = _baseRatePerYear;
        slopePerYearFirst = _slopePerYearFirst;
        slopePerYearSecond = _slopePerYearSecond;
        optimal = _optimal;
    }

    /// @notice Utilization rate 조회
    /// @dev Utilization rate = Borrows / (Supplies - Reserves)
    ///      Supplies = Cash + Borrows
    /// @param cash Underlying token amount in gToken contract
    /// @param borrows borrow amount
    /// @param reserves reserve amount
    function utilizationRate(uint256 cash, uint256 borrows, uint256 reserves) public pure returns (uint256) {
        if (reserves >= cash.add(borrows)) return 0;
        return Math.min(borrows.mul(1e18).div(cash.add(borrows).sub(reserves)), 1e18);
    }

    /// @notice Interest rate (Borrow rate) 조회
    /// @param cash Underlying token amount in gToken contract
    /// @param borrows borrow amount
    /// @param reserves reserve amount
    function getBorrowRate(uint256 cash, uint256 borrows, uint256 reserves) public view override returns (uint256) {
        uint256 utilization = utilizationRate(cash, borrows, reserves);
        if (optimal > 0 && utilization < optimal) {
            return baseRatePerYear.add(utilization.mul(slopePerYearFirst).div(optimal)).div(365 days);
        } else {
            uint256 ratio = utilization.sub(optimal).mul(1e18).div(uint256(1e18).sub(optimal));
            return baseRatePerYear.add(slopePerYearFirst).add(ratio.mul(slopePerYearSecond).div(1e18)).div(365 days);
        }
    }

    /// @notice Interest rate (Borrow rate) 조회
    /// @param cash Underlying token amount in gToken contract
    /// @param borrows borrow amount
    /// @param reserves reserve amount
    function getSupplyRate(
        uint256 cash,
        uint256 borrows,
        uint256 reserves,
        uint256 reserveFactor
    ) public view override returns (uint256) {
        uint256 oneMinusReserveFactor = uint256(1e18).sub(reserveFactor);
        uint256 borrowRate = getBorrowRate(cash, borrows, reserves);
        uint256 rateToPool = borrowRate.mul(oneMinusReserveFactor).div(1e18);
        return utilizationRate(cash, borrows, reserves).mul(rateToPool).div(1e18);
    }
}

