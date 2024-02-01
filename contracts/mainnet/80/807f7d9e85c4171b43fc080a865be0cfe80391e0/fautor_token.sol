// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ERC20Upgradeable.sol";
import "./ERC20BurnableUpgradeable.sol";
import "./ERC20SnapshotUpgradeable.sol";
import "./AccessControlUpgradeable.sol";
import "./PausableUpgradeable.sol";
import "./draft-ERC20PermitUpgradeable.sol";
import "./ERC20VotesUpgradeable.sol";
import "./ERC20FlashMintUpgradeable.sol";
import "./UUPSUpgradeable.sol";
import "./Initializable.sol";

contract Fautor is Initializable, ERC20Upgradeable, ERC20BurnableUpgradeable, ERC20SnapshotUpgradeable, AccessControlUpgradeable, PausableUpgradeable, ERC20PermitUpgradeable, ERC20VotesUpgradeable, ERC20FlashMintUpgradeable, UUPSUpgradeable {
  bytes32 public constant SNAPSHOT_ROLE = keccak256("SNAPSHOT_ROLE");
  bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
  bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
  bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");

  constructor() {
    _disableInitializers();
  }

  function initialize(string memory name, string memory symbol) initializer public {
    __ERC20_init(name, symbol);
    __ERC20Burnable_init();
    __ERC20Snapshot_init();
    __AccessControl_init();
    __Pausable_init();
    __ERC20Permit_init(name);
    __ERC20Votes_init();
    __ERC20FlashMint_init();
    __UUPSUpgradeable_init();

    _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    _grantRole(SNAPSHOT_ROLE, msg.sender);
    _grantRole(PAUSER_ROLE, msg.sender);
    _grantRole(MINTER_ROLE, msg.sender);
    _grantRole(UPGRADER_ROLE, msg.sender);
    _mint(msg.sender, 2500000000 * 10 ** decimals());
  }

  function snapshot() public onlyRole(SNAPSHOT_ROLE) {
    _snapshot();
  }

  function pause() public onlyRole(PAUSER_ROLE) {
    _pause();
  }

  function unpause() public onlyRole(PAUSER_ROLE) {
    _unpause();
  }

  function mint(address to, uint256 amount) public onlyRole(MINTER_ROLE) {
    _mint(to, amount);
  }

  function _beforeTokenTransfer(address from, address to, uint256 amount)
    internal
    whenNotPaused
    override(ERC20Upgradeable, ERC20SnapshotUpgradeable)
  {
    super._beforeTokenTransfer(from, to, amount);
  }

  function _authorizeUpgrade(address newImplementation)
    internal
    onlyRole(UPGRADER_ROLE)
    override
  {}

  function _afterTokenTransfer(address from, address to, uint256 amount)
    internal
    override(ERC20Upgradeable, ERC20VotesUpgradeable)
  {
    super._afterTokenTransfer(from, to, amount);
  }

  function _mint(address to, uint256 amount)
    internal
    override(ERC20Upgradeable, ERC20VotesUpgradeable)
  {
    super._mint(to, amount);
  }

  function _burn(address account, uint256 amount)
    internal
    override(ERC20Upgradeable, ERC20VotesUpgradeable)
  {
    super._burn(account, amount);
  }
}
