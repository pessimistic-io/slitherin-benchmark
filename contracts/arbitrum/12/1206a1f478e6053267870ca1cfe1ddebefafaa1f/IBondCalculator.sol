// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

interface IBondCalculator {
    function valuation( address _LP, uint _amount ) external view returns ( uint );
    function markdown( address _LP ) external view returns ( uint );
}
