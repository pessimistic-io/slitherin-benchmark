// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ERC20.sol";
import "./ERC20Burnable.sol";
import "./ERC20Snapshot.sol";
import "./AccessControl.sol";
import "./Pausable.sol";
import "./draft-ERC20Permit.sol";

contract CanvasToken is ERC20, ERC20Burnable, ERC20Snapshot, AccessControl, Pausable, ERC20Permit {
  bytes32 public constant SNAPSHOT_ROLE = keccak256("SNAPSHOT_ROLE");
  bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

  constructor() ERC20("CanvasToken", "CANVAS") ERC20Permit("CanvasToken") {
    _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
    _setupRole(SNAPSHOT_ROLE, msg.sender);
    _setupRole(PAUSER_ROLE, msg.sender);
    _mint(msg.sender, 40000 * 10 ** decimals());
  }

  function snapshot() public {
    require(hasRole(SNAPSHOT_ROLE, msg.sender));
    _snapshot();
  }

  function pause() public {
    require(hasRole(PAUSER_ROLE, msg.sender));
    _pause();
  }

  function unpause() public {
    require(hasRole(PAUSER_ROLE, msg.sender));
    _unpause();
  }

  function _beforeTokenTransfer(address from, address to, uint256 amount)
  internal
  whenNotPaused
  override(ERC20, ERC20Snapshot)
  {
    super._beforeTokenTransfer(from, to, amount);
  }
}
