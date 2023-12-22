// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.7.5;

interface IBondingCalculator {
    function valuation( address pair_, uint amount_, uint256 _baseValue ) external view returns ( uint _value );
}
