// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";
import "./ERC20PausableUpgradeable.sol";
import "./OwnableUpgradeable.sol";

contract xEZIOV1 is Initializable, ERC20PausableUpgradeable, OwnableUpgradeable {

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  function initialize(string memory name_,string memory symbol_) external initializer {
    __xEZIO_init(name_,symbol_);
  }

  function __xEZIO_init(string memory name_,string memory symbol_) internal onlyInitializing {
    __ERC20_init(name_, symbol_);
    __Pausable_init();
    __Ownable_init();
    __xEZIO_init_unchained();
  }

  function __xEZIO_init_unchained() internal onlyInitializing {
  }

  /**
  * @notice          Mining token
  * @param to        Account to obtain the token
  * @param amount    Mining quantity
  */
  function mint(address to, uint256 amount) public virtual onlyOwner{
    _mint(to,amount);
  }

  /**
  * @notice          Burning token
  * @param amount    Burning quantity
  */
  function burn(uint256 amount) public virtual {
    _burn(msg.sender,amount);
  }

  /**
  * @notice        Pausing the transfer function
  */
  function pause() external onlyOwner{
    _pause();
  }

  /**
  * @notice        Resuming the transfer function
  */
  function unpause() external onlyOwner{
    _unpause();
  }

  uint256[50] private __gap;

}

