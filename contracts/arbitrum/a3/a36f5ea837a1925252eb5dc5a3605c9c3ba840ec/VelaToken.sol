// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./ERC20Upgradeable.sol";
import "./PausableUpgradeable.sol";
import "./AccessControlUpgradeable.sol";
import "./Initializable.sol";

contract VelaToken is Initializable, ERC20Upgradeable, PausableUpgradeable, AccessControlUpgradeable {

    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    
    uint256 private _maxSupply;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _admin) initializer public {
        __ERC20_init("VelaToken", "VELA");
        __Pausable_init();
        __AccessControl_init();
        _maxSupply = 100000000 * 10**decimals(); // 100M tokens is maximum supply

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(PAUSER_ROLE, _admin);
        _grantRole(MINTER_ROLE, _admin);
    }

    /**
     * @dev Returns the maximum amount of tokens that can be minted.
     */
    function maxSupply() public view returns (uint256) {
        return _maxSupply;
    }

    function pause() public onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() public onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    function mint(address to, uint256 amount) public onlyRole(MINTER_ROLE) {
        require(totalSupply() + amount <= _maxSupply, "ERC20: cannot mint more tokens, cap exceeded");
        _mint(to, amount);
    }

    function _beforeTokenTransfer(address from, address to, uint256 amount)
        internal
        whenNotPaused
        override
    {
        super._beforeTokenTransfer(from, to, amount);
    }
}

