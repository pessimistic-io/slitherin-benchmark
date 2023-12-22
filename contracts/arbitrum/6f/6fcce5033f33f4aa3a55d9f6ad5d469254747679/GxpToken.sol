// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;
import "./ERC20.sol";
import "./draft-ERC20Permit.sol";
import "./Ownable2Step.sol";
import { ITokenMinterMulti } from "./Common.sol";

contract GxpToken is ITokenMinterMulti, ERC20, Ownable2Step, ERC20Permit {
  bool public inPrivateTransferMode;
  mapping(address => bool) public isHandler;
  mapping(address => bool) public isMinter;

  constructor() ERC20('Grailx by Plutus', 'GXP') ERC20Permit('Grailx by Plutus') {
    inPrivateTransferMode = true;
  }

  function mint(address _to, uint256 _amount) external {
    if (!isMinter[msg.sender]) revert UNAUTHORIZED();
    _mint(_to, _amount);
  }

  function burn(address _from, uint256 _amount) external {
    if (!isMinter[msg.sender]) revert UNAUTHORIZED();
    _burn(_from, _amount);
  }

  /** OVERRIDES */

  ///@dev Transfers are permissioned, handlers have the ability to transfer and transferFrom.
  function _transfer(address from, address to, uint256 amount) internal override {
    if (!inPrivateTransferMode || isHandler[msg.sender]) {
      super._transfer(from, to, amount);
    } else {
      revert UNAUTHORIZED();
    }
  }

  /** OWNER FUNCTIONS */
  function updateMinter(address _minter, bool _isActive) external onlyOwner {
    isMinter[_minter] = _isActive;
    emit MinterUpdated(_minter, _isActive);
  }

  function setInPrivateTransferMode(bool _inPrivateTransferMode) external onlyOwner {
    inPrivateTransferMode = _inPrivateTransferMode;
    emit InPrivateTransferMode(_inPrivateTransferMode);
  }

  function updateHandler(address _handler, bool _isActive) external onlyOwner {
    isHandler[_handler] = _isActive;
    emit HandlerUpdated(_handler, _isActive);
  }

  event HandlerUpdated(address indexed _address, bool _isActive);
  event MinterUpdated(address indexed _address, bool _isActive);
  event InPrivateTransferMode(bool _isInPrivateTransferMode);

  error UNAUTHORIZED();
}

