// SPDX-License-Identifier: MIT

pragma solidity ^0.8.12;

import "./ERC20.sol";
import "./Ownable.sol";
import "./Context.sol";
import "./IERC20BurnableMinter.sol";

contract Labs is Context, Ownable, ERC20 {
  address buyback;
  bool buyBackSet = false;
  /**
   * See {ERC20-constructor}.
   */
  constructor() ERC20("Labs", "LABS") {}

  /**
   * @dev Creates `amount` new tokens for `to`.
   *
   * See {ERC20-_mint}.
   *
   * Requirements:
   *
   * - the caller is the owner.
   */
  function mint(address to, uint256 amount) public virtual onlyOwner {
    _mint(to, amount);
  }

function setBuyBack(address _buyback) external onlyOwner {
  require(!buyBackSet, "AlreadySet");
  buyback = _buyback;
}

  function mintForBuyBack( uint256 amount) external virtual  {
    require(msg.sender == buyback, "JustBuyback");
    _mint(msg.sender, amount);
  }
  /**
   * @dev Destroys `amount` tokens from the caller.
   *
   * See {ERC20-_burn}.
   *
   * Requirements:
   *
   * - the caller is the owner.
   */
  function burn(uint256 amount) public virtual onlyOwner {
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
   * - the caller is the owner.
   * - the caller must have allowance for ``accounts``'s tokens of at least
   * `amount`.
   */
  function burnFrom(address account, uint256 amount) public virtual onlyOwner {
    _spendAllowance(account, _msgSender(), amount);
    _burn(account, amount);
  }
}

