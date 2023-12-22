// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.7.6;
pragma abicoder v2;

import "./SafeMath.sol";
import "./SignedSafeMath.sol";
import "./SafeCast.sol";
import "./IManager.sol";
import "./WadRayMath.sol";

contract InterestLogic {
    using SafeMath for uint256;
    using SignedSafeMath for int256;
    using SignedSafeMath for int8;
    using SafeCast for int256;
    using SafeCast for uint256;
    using WadRayMath for uint256;

    uint256 public constant SECONDS_PER_HOUR = 1 hours; //seconds per hour
    uint256 public constant RATE_PRECISION = 1e6;       //rate decimal 1e6
    address public manager;                             //manager address

    // hourly max interests, scaled by 1e27
    mapping(address => uint256) ratePerHours;

    event UpdateRatePerHour(address pool, uint256 rate);

    constructor(address _manager){
        require(_manager != address(0), "InterestLogic: manager is zero address");
        manager = _manager;
    }

    modifier onlyController() {
        require(IManager(manager).checkController(msg.sender), "InterestLogic: Must be controller");
        _;
    }
    
    /// @notice update the max hourly interests ratio
    /// @param _pool pool address
    /// @param _ratePerHour rate per hour
    function updateRatePerHour(address _pool, uint256 _ratePerHour) external onlyController {
        ratePerHours[_pool] = _ratePerHour;
        emit UpdateRatePerHour(_pool, _ratePerHour);
    }

    /// @notice calculate utilization ratio
    /// @param usedAmount used amount
    /// @param totalAmount total amount
    /// @param reserveRate reserve rate
    /// @return utilization ratio scaled 1e27
    function utilizationRatio(uint256 usedAmount, uint256 totalAmount, uint256 reserveRate) public view returns (uint256) {
        if (usedAmount == 0) return 0;
        uint256 availableTotal = totalAmount.mul(RATE_PRECISION.sub(reserveRate)).div(RATE_PRECISION);
        return usedAmount.rayDiv(availableTotal);
    }

    /// @notice calculate current hourly interests ratio
    /// @param _pool pool address
    /// @param usedAmount used amount
    /// @param totalAmount total amount
    /// @param reserveRate reserve rate
    /// @return borrowRate scaled 1e27
    function getBorrowRate(address _pool, uint256 usedAmount, uint256 totalAmount, uint256 reserveRate) public view returns (uint256 borrowRate) {
        uint256 _util = utilizationRatio(usedAmount, totalAmount, reserveRate);
        borrowRate = _util.rayMul(ratePerHours[_pool]);
        borrowRate = borrowRate > ratePerHours[_pool] ? ratePerHours[_pool] : borrowRate;
    }
    
    /**
    * @dev Function to calculate the interest using a compounded interest rate formula
    * To avoid expensive exponentiation, the calculation is performed using a binomial approximation:
    *
    *  (1+x)^n = 1+n*x+[n/2*(n-1)]*x^2+[n/6*(n-1)*(n-2)]*x^3...
    *
    * The approximation slightly underpays liquidity providers and undercharges borrowers, with the advantage of great
    * gas cost reductions.

    * @notice calculate current interest
    * @param interestRate interest rate per hour
    * @param deltaTs delta time
    * @return interest scaled 1e27
    */
    function calculateCompoundedInterest(uint256 interestRate, uint256 deltaTs) internal view returns (uint256) {
        uint256 expMinusOne = deltaTs > 1 ? deltaTs - 1 : 0;
        uint256 expMinusTwo = deltaTs > 2 ? deltaTs - 2 : 0;

        interestRate = interestRate.div(SECONDS_PER_HOUR);

        uint256 basePowerTwo = interestRate.rayMul(interestRate);
        uint256 basePowerThree = basePowerTwo.rayMul(interestRate);

        uint256 secondTerm = deltaTs.mul(expMinusOne).mul(basePowerTwo).div(2);
        uint256 thirdTerm = deltaTs.mul(expMinusOne).mul(expMinusTwo).mul(basePowerThree).div(6);

        return WadRayMath.RAY.add(interestRate.mul(deltaTs)).add(secondTerm).add(thirdTerm);
    }

    /// @notice calculate interests global cumulative data
    /// @param _pool pool address
    /// @param usedAmount used amount
    /// @param totalAmount total amount
    /// @param reserveRate reserve rate
    /// @param lastUpdateTs last update time
    /// @param borrowInterestGrowthGlobal last interest global cumulative
    /// @return borrowRate borrow rate scaled 1e27
    /// @return borrowIg borrow interest growth scaled 1e27
    function getMarketBorrowIG(address _pool, uint256 usedAmount, uint256 totalAmount, uint256 reserveRate, uint256 lastUpdateTs, uint256 borrowInterestGrowthGlobal) public view returns (uint256 borrowRate, uint256 borrowIg) {
        borrowRate = getBorrowRate(_pool, usedAmount, totalAmount, reserveRate);
        if (lastUpdateTs == 0) return (0, WadRayMath.RAY);
        uint256 deltaTs = block.timestamp - lastUpdateTs;
        if (deltaTs == 0 || IManager(manager).isInterestPaused()) return (0, borrowInterestGrowthGlobal);
        borrowIg = borrowInterestGrowthGlobal.rayMul(calculateCompoundedInterest(borrowRate, deltaTs));
        return (borrowRate, borrowIg);
    }

    /// @notice calculate borrow share
    /// @param amount amount
    /// @param borrowIg borrow interest growth
    /// @return borrow share
    function getBorrowShare(uint256 amount, uint256 borrowIg) public view returns (uint256) {
        return amount.rayDiv(borrowIg);
    }

    /// @notice calculate borrow amount
    /// @param borrowShare borrow share
    /// @param borrowIg borrow interest growth
    /// @return  borrow amount with the same precision of amount for the calculation when borrow
    function getBorrowAmount(uint256 borrowShare, uint256 borrowIg) public view returns (uint256) {
        return borrowShare.rayMul(borrowIg);
    }
}

