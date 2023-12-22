pragma solidity 0.8.18;

import {IInterestRateModel} from "./IInterestRateModel.sol";

contract SimpleInterestRateModel is IInterestRateModel {
    /// @notice interest rate model
    uint256 public interestRate;

    constructor(uint256 _interestRate) {
        interestRate = _interestRate;
    }

    function getBorrowRatePerInterval(uint256 _totalCash, uint256 _utilization) external view returns (uint256) {
        return _totalCash == 0 ? 0 : interestRate * _utilization / _totalCash;
    }
}

