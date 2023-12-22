// SPDX-License-Identifier: MIT 

pragma solidity ^0.8.17;

interface IVaultFactory {
     function createVault(
         address _pool, 
         string memory _name,
          string memory _symbol,
           address _ram, 
           address _neadRam,
           address _rewarder
           ) external returns (address);
}
