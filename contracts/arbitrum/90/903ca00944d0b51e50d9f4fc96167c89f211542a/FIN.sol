// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.18;

import {ERC20} from "./ERC20.sol";
import {Ownable} from "./Ownable.sol";

contract FIN is ERC20, Ownable {

  /**
   * @notice The max total supply of the token
   */
  uint256 public constant MAX_SUPPLY = 20_000_000e18;

  /**
   * @notice Thrown in case the MAX_SUPPLY is exceeded
   */
  error MaxSupplyExceeded();

  /**
   * @notice Constructs the initial config of the ERC20
   *
   * @param _owner The owner which can mint new tokens
   */
  constructor(
    address _owner
  ) ERC20() {
    _transferOwnership(_owner);
    owner = _owner;
  }

  /**
   * @notice Mints tokens for a user
   * @dev Can only be called by a bridge
   * @param _user The address of the user who needs tokens minted
   * @param _amount The amount of tokens being minted
   */
  function mint(address _user, uint256 _amount) public onlyOwner() {
    if (_amount + totalSupply() > MAX_SUPPLY) {
      revert MaxSupplyExceeded();
    }
    _mint(_user, _amount);
  }

  /**
   * @notice Burns tokens for a user
   * @dev Can only be called by a bridge
   * @param _user The address of the user who needs tokens burned
   * @param _amount The amount of tokens being burned
   */
  function burn(address _user, uint256 _amount) public {
    if (msg.sender != _user) {
      _spendAllowance(_user, msg.sender, _amount);
    }
    _burn(_user, _amount);
  }

    
  /// @dev Returns the name of the token.
  function name() public pure override returns (string memory) {
      return 'Poolshark';
  }

  /// @dev Returns the symbol of the token.
  function symbol() public pure override returns (string memory) {
      return 'FIN';
  }
}

