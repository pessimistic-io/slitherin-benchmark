//SPDX-License-Identifier: MIT

import "./DSMath.sol";
pragma solidity ^0.8.17;

contract RewardCalculator is DSMath {
    function calculateInteresetInSeconds(
        uint256 principal,
        uint256 apy,
        uint256 _seconds
    ) public pure returns (uint256) {
        uint256 _ratio = ratio(apy);
        return accrueInterest(principal, _ratio, _seconds);
    }

    function ratio(uint256 n) internal pure returns (uint256) {
        uint256 numerator = n * 10 ** 25;
        uint256 denominator = 365 * 86400;
        uint256 result = uint256(10 ** 27) + uint256(numerator / denominator);
        return result;
    }

    function accrueInterest(
        uint _principal,
        uint _rate,
        uint _age
    ) internal pure returns (uint) {
        return rmul(_principal, rpow(_rate, _age));
    }
}

