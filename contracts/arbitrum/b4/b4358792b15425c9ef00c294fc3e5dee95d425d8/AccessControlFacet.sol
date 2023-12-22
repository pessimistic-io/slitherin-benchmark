// SPDX-License-Identifier: UNLINCESED
pragma solidity 0.8.20;

import { LibAccessControl } from "./LibAccessControl.sol";
import { LibDiamond } from "./LibDiamond.sol";

error CannotAuthoriseSelf();

contract AccessControlFacet {

    event AccessGranted(address indexed account, bytes4 indexed selector);
    event AccessRevoked(address indexed account, bytes4 indexed selector);

    function grantAccess(address _account, bytes4 _selector) external {
        if (msg.sender == address(this)) revert CannotAuthoriseSelf();
        LibDiamond.enforceIsContractOwner();

        LibAccessControl.addAccess(_account, _selector);
        emit AccessGranted(_account, _selector);
    }

    function revokeAccess(address _account, bytes4 _selector) external {
        if (msg.sender == address(this)) revert CannotAuthoriseSelf();
        LibDiamond.enforceIsContractOwner();

        LibAccessControl.revokeAccess(_account, _selector);
        emit AccessRevoked(_account, _selector);
    }

    function hasAccess(address _account, bytes4 _selector) external view returns (bool) {
        return LibAccessControl._getStorage().functionAccess[_account][_selector];
    }
}
