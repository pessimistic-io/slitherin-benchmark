// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

interface IUniV3BondingCalculator {
  function valuation( address _pool, uint256 _tokenId ) external view returns ( uint _value );
  function markdown( address _pool, uint256 _tokenId ) external view returns ( uint );
}
