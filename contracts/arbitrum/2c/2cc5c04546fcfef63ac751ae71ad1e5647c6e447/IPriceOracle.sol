// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

interface IPriceOracle {
    struct Price {
        uint256 base;
        uint256 premium;
    }
    
    function price(
        string calldata name,
        uint256 expires,
        uint256 duration
    ) external view returns (Price calldata);

}

