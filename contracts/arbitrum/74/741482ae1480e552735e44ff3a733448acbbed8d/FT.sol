// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;
import "./ERC20.sol";
import "./ERC20Burnable.sol";
import "./AccessControl.sol";

contract FT is ERC20, ERC20Burnable, AccessControl {
  bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
  uint256 public immutable supplyLimit;

  constructor(
    string memory name_,
    string memory symbol_,
    uint256 _supplyLimt
  ) ERC20(name_, symbol_) {
    _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
    _setupRole(MINTER_ROLE, msg.sender);
    supplyLimit = _supplyLimt;
  }

  function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) {
    if (supplyLimit > 0) {
      require(
        (totalSupply() + amount) <= supplyLimit,
        "Exceed the total supply"
      );
    }
    _mint(to, amount);
  }

  function setMintRole(address to) external {
    grantRole(MINTER_ROLE, to);
  }

  function removeMintRole(address to) external {
    revokeRole(MINTER_ROLE, to);
  }
}

