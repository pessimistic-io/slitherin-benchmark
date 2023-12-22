// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./draft-ERC20PermitUpgradeable.sol";
import "./ERC20BurnableUpgradeable.sol";
import "./ERC20CappedUpgradeable.sol";
import "./AccessControlUpgradeable.sol";
import "./ERC20Upgradeable.sol";
import "./PausableUpgradeable.sol";
import "./Initializable.sol";

/**
* @title EVO v1.0.0
* @author @DirtyCajunRice
*/
contract EVOUpgradeable is Initializable, ERC20Upgradeable, ERC20BurnableUpgradeable, ERC20CappedUpgradeable,
PausableUpgradeable, AccessControlUpgradeable, ERC20PermitUpgradeable {
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize() public initializer {
        __ERC20_init("EVO", "EVO");
        __ERC20Burnable_init();
        __ERC20Capped_init(600_000_000 ether);
        __Pausable_init();
        __AccessControl_init();
        __ERC20Permit_init("EVO");

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
        _grantRole(MINTER_ROLE, msg.sender);
    }

    function pause() public onlyRole(ADMIN_ROLE) {
        _pause();
    }

    function unpause() public onlyRole(ADMIN_ROLE) {
        _unpause();
    }

    function mint(address to, uint256 amount) public onlyRole(MINTER_ROLE) {
        _mint(to, amount);
    }

    function _mint(address to, uint256 amount) internal override(ERC20Upgradeable, ERC20CappedUpgradeable) {
        super._mint(to, amount);
    }

    function _beforeTokenTransfer(address from, address to, uint256 amount) internal whenNotPaused override {
        super._beforeTokenTransfer(from, to, amount);
    }
}
