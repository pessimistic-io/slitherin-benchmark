// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.15;

import { OrganizationManagement } from "./OrganizationManagement.sol";
import { Base } from "./Base.sol";
import { Charge } from "./Charge.sol";
import { IDiagonalOrg } from "./IDiagonalOrg.sol";
import { Initializable } from "./Initializable.sol";

contract DiagonalOrg is IDiagonalOrg, Initializable, Base, Charge, OrganizationManagement {
    /*******************************
     * Constants *
     *******************************/

    string public constant VERSION = "1.0.0";

    /*******************************
     * State vars *
     *******************************/

    /**
     * @notice Gap array, for further state variable changes
     */
    uint256[50] private __gap;

    /*******************************
     * Constructor *
     *******************************/

    constructor() {
        // Prevent the implementation contract from being initilised and re-initilised
        _disableInitializers();
    }

    /*******************************
     * Functions start *
     *******************************/

    function initialize(address _signer) external onlyInitializing {
        signer = _signer;
    }
}

