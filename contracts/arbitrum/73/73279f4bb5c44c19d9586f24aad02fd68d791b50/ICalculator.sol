// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

interface ICalculator {
    function getAUME30(bool _isMaxPrice) external view returns (uint256);

    function getHLPPrice(uint256 _aum, uint256 _hlpSupply) external pure returns (uint256);
}

