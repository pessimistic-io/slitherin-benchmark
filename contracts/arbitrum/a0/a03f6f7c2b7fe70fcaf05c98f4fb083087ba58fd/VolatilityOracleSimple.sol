// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import {Ownable} from "./Ownable.sol";

contract VolatilityOracleSimple is Ownable {
    uint256 volatility = 30;

    function getVolatility(uint256 _strike) external view returns (uint256) {
        return volatility;
    }

    function updateVolatility(uint256 _volatility) external {
        volatility = _volatility;
    }
}

