// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { Address } from "./Address.sol";
import { AccessControl } from "./AccessControl.sol";
import { Address } from "./Address.sol";
import { Constants } from "./Constants.sol";
import { SwapAdapterRegistry } from "./SwapAdapterRegistry.sol";

error notOwner();
error notContract();

contract Controller is AccessControl, SwapAdapterRegistry {
    using Address for address;

    // Addresses of Taurus contracts

    address public immutable tau;
    address public immutable tgt;

    mapping(bytes32 => address) public addressMapper;

    // Functions

    /**
     * @param _tau address of the TAU token
     * @param _tgt address of the TGT token
     * @param _governance address of the Governor
     * @param _multisig address of the team multisig
     */
    constructor(address _tau, address _tgt, address _governance, address _multisig) {
        tau = _tau;
        tgt = _tgt;

        // Set up access control
        _setupRole(DEFAULT_ADMIN_ROLE, _governance);
        _setupRole(Constants.MULTISIG_ROLE, _multisig);
        _setRoleAdmin(Constants.KEEPER_ROLE, Constants.MULTISIG_ROLE); // Set multisig as keeper manager
    }

    function setAddress(bytes32 _name, address _addr) external onlyRole(DEFAULT_ADMIN_ROLE) {
        addressMapper[_name] = _addr;
    }
}

