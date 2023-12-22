// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./AccessControlEnumerable.sol";
import "./Pausable.sol";

contract SecurityBase is AccessControlEnumerable, Pausable {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    modifier onlyMinter() {
        _checkRole(MINTER_ROLE, _msgSender());
        _;
    }

    modifier onlyAdmin() {
        _checkRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _;
    }

    constructor() {
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _setupRole(MINTER_ROLE, _msgSender());
    }

    function pause() external onlyMinter {
        _pause();
    }

    function unpause() external onlyMinter {
        _unpause();
    }

    function grantMinter(address account) 
        external 
        virtual 
        onlyMinter
    {
        _setupRole(MINTER_ROLE, account);
    }

    function revokeMinter(address account)
        external
        virtual
        onlyMinter
    {
        _revokeRole(MINTER_ROLE, account);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(AccessControlEnumerable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}
