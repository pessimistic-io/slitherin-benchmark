// SPDX-License-Identifier: UNLINCESED
pragma solidity 0.8.20;

import { CannotAuthoriseSelf } from "./GenericErrors.sol";

error NotAllowedTo(address account, bytes4 selector);

library LibAccessControl {
    bytes32 internal constant ACCESS_CONTROL_STORAGE = keccak256("access.control.storage");

    struct AccessStorage {
        mapping(address => mapping(bytes4 => bool)) functionAccess;
    }

    event AccessGranted(address indexed account, bytes4 indexed selector);
    event AccessRevoked(address indexed account, bytes4 indexed selector);

    function _getStorage() internal pure returns (AccessStorage storage accStor) {
        bytes32 position = ACCESS_CONTROL_STORAGE;
        assembly {
            accStor.slot := position
        }
    }

    function addAccess(address _account, bytes4 _selector) internal {
        if (_account == address(this)) revert CannotAuthoriseSelf();
        AccessStorage storage accStor = _getStorage();  
        accStor.functionAccess[_account][_selector] = true;
        emit AccessGranted(_account, _selector);
    }

    function revokeAccess(address _account, bytes4 _selector) internal {
        AccessStorage storage accStor = _getStorage();
        accStor.functionAccess[_account][_selector] = false;
        emit AccessRevoked(_account, _selector);
    }

    function isAllowedTo() internal view {
        AccessStorage storage accStor = _getStorage();
        if (!accStor.functionAccess[msg.sender][msg.sig]) revert NotAllowedTo(msg.sender, msg.sig);
    }
}
