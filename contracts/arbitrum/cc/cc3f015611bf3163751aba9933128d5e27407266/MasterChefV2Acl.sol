pragma solidity ^0.8.0;

import "./BaseCoboSafeModuleAcl.sol";

contract MasterChefV2Acl is BaseCoboSafeModuleAcl {

    constructor(
        address _safeAddress,
        address _safeModule
    ) {
        _setSafeAddressAndSafeModule(_safeAddress, _safeModule);
    }

    function withdraw(uint256 pid, uint256 amount, address to) 
        external
        view 
        onlySelf 
    {
        onlySafeAddress(to);
    }

    function deposit(uint256 pid, uint256 amount, address to) 
        external
        view 
        onlySelf
    {
        onlySafeAddress(to);
    }

    function withdrawAndHarvest(uint256 pid, uint256 amount, address to) 
        external
        view 
        onlySelf 
    {
        onlySafeAddress(to);
    }
}
