// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./draft-ERC20Permit.sol";
import "./ERC20Burnable.sol";
import "./AccessControl.sol";
import "./Ownable.sol";
import "./Pausable.sol";
import "./SafeERC20.sol";

contract DuoToken is ERC20Burnable, ERC20Permit, AccessControl, Pausable {
    using SafeERC20 for IERC20;

    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant RESCUER_ROLE = keccak256("RESCUER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    mapping(address => bool) public blacklist;

    constructor() ERC20("DUO", "DUO") ERC20Permit("DUO") {
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(PAUSER_ROLE, msg.sender);
        _setupRole(MINTER_ROLE, msg.sender);
        _setupRole(RESCUER_ROLE, msg.sender);
    }

    function mint(address to, uint256 amount) public onlyRole(MINTER_ROLE) {
        _mint(to, amount);
    }

    function pause() public onlyRole(PAUSER_ROLE) {
        // pause token transfers in case of emergency
        _pause();
    }

    function unpause() public onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal override whenNotPaused {
        super._beforeTokenTransfer(from, to, amount);
    }

    function rescueTokens(
        IERC20 token,
        uint256 value
    ) external onlyRole(RESCUER_ROLE) {
        token.transfer(msg.sender, value);
    }

    function setBlacklistAddress(
        address _address,
        bool _status
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        blacklist[_address] = _status;
    }
}

