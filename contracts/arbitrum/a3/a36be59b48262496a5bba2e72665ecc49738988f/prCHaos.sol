// SPDX-License-Identifier: MIT

pragma solidity ^0.8.12;

import "./AccessControlEnumerable.sol";
import "./ERC20.sol";
import "./Context.sol";
import "./IERC20BurnableMinter.sol";

contract prLab is Context, ERC20, AccessControlEnumerable {
  bytes32 public constant MINT_ROLE = keccak256("MINT_ROLE");

  /**
   * See {ERC20-constructor}.
   */
  constructor() ERC20("prLabs", "prLabs") {
    _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
  }

  /**
   * @dev Creates `amount` new tokens for `to`.
   *
   * See {ERC20-_mint}.
   *
   * Requirements:
   *
   * - the caller has MINT_ROLE.
   */
  function mint(address to, uint256 amount) public virtual onlyRole(MINT_ROLE) {
    _mint(to, amount);
  }

  /**
   * @dev Destroys `amount` tokens from the caller.
   *
   * See {ERC20-_burn}.
   */
  function burn(uint256 amount) public virtual {
    _burn(_msgSender(), amount);
  }

  /**
   * @dev Destroys `amount` tokens from `account`, deducting from the caller's
   * allowance.
   *
   * See {ERC20-_burn} and {ERC20-allowance}.
   *
   * Requirements:
   *
   * - the caller must have allowance for ``accounts``'s tokens of at least
   * `amount`.
   */
  function burnFrom(address account, uint256 amount) public virtual {
    _spendAllowance(account, _msgSender(), amount);
    _burn(account, amount);
  }
}

