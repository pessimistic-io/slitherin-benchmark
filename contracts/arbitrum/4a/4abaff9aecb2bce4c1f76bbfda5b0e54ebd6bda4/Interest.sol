pragma solidity ^0.8.0;

import "./IInterest.sol";
import "./Math.sol";
import "./IModel.sol";
import "./Initializable.sol";

/// @notice Tracks accrewed interest
contract Interest is IInterest, Initializable {
    using Math for uint;

    uint constant ONE    = 10**18;
    uint constant ONE_26 = 10**26;
    uint constant ONE_8 = 10**8;
    uint constant COMPOUNDING_PERIOD = 3600;  // 1 hour

    /// @notice 1 + hourly interest rate. < 1 represents a negative rate
    /// @dev 18-decimal fixed-point
    uint public rate;

    /// @notice Timestamp of when interest began accrewing
    /// @dev start at a perfect multiple of COMPOUNDING_PERIOD so all contracts are synced
    uint internal startTime;

    /// @notice Value of accumulated interest multiplier when interest began accrewing
    /// @dev 26-decimal fixed-point
    uint internal startValue;

    function initialize() internal onlyInitializing {
        rate = ONE;
        startTime = (block.timestamp / COMPOUNDING_PERIOD) * COMPOUNDING_PERIOD;
        startValue = ONE_26;
    }

    /// @notice Accrewed interest multiplier. Nominal value of 1 hedge token in denominating currency
    /// @return Target currency-hedge exchange rate, expressed as denominating currency per hedge token. 26-decimal fixed-point 
    function accrewedMul() public view returns (uint) {
        unchecked {
            return startValue * (rate*ONE_8).pow((block.timestamp - startTime) / COMPOUNDING_PERIOD) / ONE_26;
        }
    }

    /// @notice Update interest rate according to model
    function _updateRate(IModel model, uint potValue, uint hedgeTV, uint _accrewedMul) internal {
        uint _rate = uint(int(ONE) + model.getInterestRate(potValue, hedgeTV));
        if (_rate != rate) {
            _setRate(_rate, _accrewedMul);
        }
    }

    /// @notice Change the hourly interest rate. May represent a negative rate.
    /// @param _rate 18-decimal fixed-point. 1 + hourly interest rate.
    function _setRate(uint _rate, uint _accrewedMul) internal {
        startValue = _accrewedMul;
        startTime = startTime + (((block.timestamp - startTime) / COMPOUNDING_PERIOD) * COMPOUNDING_PERIOD);
        rate = _rate;
    }
}
