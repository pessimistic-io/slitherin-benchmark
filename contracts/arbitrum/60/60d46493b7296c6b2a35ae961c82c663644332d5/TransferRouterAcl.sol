pragma solidity ^0.8.0;

import "./BaseCoboSafeModuleAcl.sol";
import "./AddressAccessControl.sol";


contract TransferRouterAcl is BaseCoboSafeModuleAcl,
    AddressAccessControl {

    constructor(
        address _safeAddress,
        address _safeModule,
        address[] memory whiteList
    ) {
        _setSafeAddressAndSafeModule(_safeAddress, _safeModule);
        _addAddresses(whiteList);
    }


    /// @dev check if a role has the permission to transfer ETH
    /// @param roles the roles to check
    /// @param receiver ETH receiver
    /// @param value ETH value
    /// @return true|false
    function check(bytes32[] memory roles, address receiver, uint256 value) external view onlyModule returns (bool)  {
         return contains(receiver);
    }

    function transfer(address token,address _to, uint256 _value) external view onlySelf {
        _checkAddress(_to);
    }

}


