pragma solidity 0.8.10;


library AspisLibrary {

    uint256 private constant SECONDS_IN_YEAR = 365 * 24 * 60 * 60;

    function calculateProRataShare(
        uint256 _balance,
        uint256 _amount,
        uint256 _totalSupply
    ) internal pure returns (uint256) {
        return (_amount * _balance) / _totalSupply; //20, 8, 10 = (8 * 20 / 10) = 16
    }

    function calculatePerformanceFee(uint256 _currentPrice, uint256 _averagePrice, uint256 _withdrawAmount, uint256 _totalSupply, uint256 _poolValueUSD, uint256 _performanceFee) internal pure returns(uint256) {
        if (_currentPrice > _averagePrice) { 
                uint256 _a = (_currentPrice - _averagePrice) * _withdrawAmount * _performanceFee; // (2000 - 1000) * (20 * 10^18) * 2000 = 4e25
                uint256 _numerator = _totalSupply * _a; // (2 * 10^18) * 4e25 = 0.8
                uint256 _denominator = (_poolValueUSD * 1e22) - _a; // (10 ** usd_decimal_places * 10 ** fee_decimal_places * 100(for percentage))
                //(40000) * (10 ** 22) - 4e25 = 3.6
                return  _numerator / _denominator;  // 0.8 / 3.6 = 0.22222
        }

        return 0;
    }

    function calculateFundManagementFee(uint256 _currentTimestamp, uint _lastFundManagementFeeTimestamp, uint256 _totalSupply, uint256 _fundManagementFee) internal pure returns(uint256) {
        uint256 _a = _fundManagementFee * (_currentTimestamp - _lastFundManagementFeeTimestamp);
        uint256 _numerator = _totalSupply * _a;
        uint256 _denominator = (SECONDS_IN_YEAR * 10**4) - _a;
        return _numerator / _denominator;
    }

    /**
    * @notice returns true if withdraws are within the withdraw period or there is no withdraw and freeze period
    */
    function isWithdrawalWithinWindow(uint256 _withdrawPeriod, uint256 _freezePeriod, uint256 _fundraisingFinishTime) internal view returns(bool) {
        
        if((_withdrawPeriod + _freezePeriod) == 0) {
            return true;
        }

        uint256 _currentTime = block.timestamp;

        //counting seconds passed after the fundraising period is over as freeze and withdraw windows start after it.
        uint256 _countPastSeconds = (_currentTime - _fundraisingFinishTime);

        //taking mod over the total past seconds between current time and fundraising finish time
        uint256 _currentRelativeDay = _countPastSeconds % (_withdrawPeriod + _freezePeriod);


        if (_currentRelativeDay >= _freezePeriod) {
            return true;
        }
        return false;
    }

    function isWithdrawalWithinFundraising(uint256 _fundraisingFinishTime) internal view returns(bool) {
        uint256 _currentTime = block.timestamp;
        //before fundraising is over
        if (_fundraisingFinishTime > _currentTime) {
            return true;  //rage quit will apply
        }

        return false;
    }

}
