//SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./AccessControlEnumerableUpgradeable.sol";
import "./PausableUpgradeable.sol";
import "./Initializable.sol";
import { IERC173 } from "./IERC173.sol";

// A base class for all contracts.
// Includes basic utility functions, access control, and the ability to pause the contract.
contract UtilitiesUpgradeable is Initializable, AccessControlEnumerableUpgradeable, PausableUpgradeable, IERC173 {
    bytes32 internal constant OWNER_ROLE = keccak256("OWNER");
    bytes32 internal constant ADMIN_ROLE = keccak256("ADMIN");
    bytes32 internal constant ROLE_GRANTER_ROLE = keccak256("ROLE_GRANTER");

    function __Utilities_init() internal onlyInitializing {
        AccessControlEnumerableUpgradeable.__AccessControlEnumerable_init();
        PausableUpgradeable.__Pausable_init();

        __Utilities_init_unchained();
    }

    function __Utilities_init_unchained() internal onlyInitializing {
        _pause();

        _grantRole(OWNER_ROLE, msg.sender);
    }

    modifier onlyEOA() {
        /* solhint-disable avoid-tx-origin */
        require(msg.sender == tx.origin, "No contracts");
        _;
    }

    modifier requiresRole(bytes32 _role) {
        require(hasRole(_role, msg.sender), "Does not have required role");
        _;
    }

    modifier requiresEitherRole(bytes32 _roleOption1, bytes32 _roleOption2) {
        require(hasRole(_roleOption1, msg.sender) || hasRole(_roleOption2, msg.sender), "Does not have required role");

        _;
    }

    function setPause(bool _shouldPause) external requiresEitherRole(ADMIN_ROLE, OWNER_ROLE) {
        if (_shouldPause) {
            _pause();
        } else {
            _unpause();
        }
    }

    function owner() external view returns (address) {
        require(getRoleMemberCount(OWNER_ROLE) == 1, "There must be exactly 1 owner");
        return getRoleMember(OWNER_ROLE, 0);
    }

    function transferOwnership(address _newOwner) external requiresRole(OWNER_ROLE) {
        _revokeRole(OWNER_ROLE, msg.sender);
        _grantRole(OWNER_ROLE, _newOwner);
        require(getRoleMemberCount(OWNER_ROLE) == 1, "There must be exactly 1 owner");

        emit OwnershipTransferred(msg.sender, _newOwner);
    }

    function grantRole(
        bytes32 _role,
        address _account
    )
        public
        override(AccessControlUpgradeable, IAccessControlUpgradeable)
        requiresEitherRole(ROLE_GRANTER_ROLE, OWNER_ROLE)
    {
        require(_role != OWNER_ROLE, "Cannot change owner role through grantRole");
        _grantRole(_role, _account);
    }

    function revokeRole(
        bytes32 _role,
        address _account
    )
        public
        override(AccessControlUpgradeable, IAccessControlUpgradeable)
        requiresEitherRole(ROLE_GRANTER_ROLE, OWNER_ROLE)
    {
        require(_role != OWNER_ROLE, "Cannot change owner role through grantRole");
        _revokeRole(_role, _account);
    }

    function supportsInterface(bytes4 _interfaceId) public view virtual override returns (bool) {
        return _interfaceId == type(IERC173).interfaceId || super.supportsInterface(_interfaceId);
    }

    function compareStrings(string memory a, string memory b) internal pure returns (bool) {
        return (keccak256(abi.encodePacked((a))) == keccak256(abi.encodePacked((b))));
    }
}

