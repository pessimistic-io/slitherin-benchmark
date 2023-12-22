// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;
import "./ERC20.sol";
import "./Ownable2Step.sol";
import "./draft-ERC20Permit.sol";
import { IBaseToken } from "./Interfaces.sol";

contract BaseToken is IBaseToken, ERC20, ERC20Permit, Ownable2Step {
  bool public inPrivateTransferMode;
  mapping(address => bool) public isHandler;
  mapping(address => bool) private allowUnsafeTransfer; //note: bypass approvals

  constructor(
    string memory _name,
    string memory _symbol,
    bool _isTransferPermissioned
  ) ERC20(_name, _symbol) ERC20Permit(_name) {
    inPrivateTransferMode = _isTransferPermissioned;
  }

  function transferFrom(address from, address to, uint256 amount) public virtual override returns (bool) {
    if (allowUnsafeTransfer[msg.sender] == false) {
      address spender = _msgSender();
      _spendAllowance(from, spender, amount);
    }

    _transfer(from, to, amount);
    return true;
  }

  function _transfer(address from, address to, uint amount) internal override {
    if (inPrivateTransferMode && !isHandler[msg.sender])
      revert UNAUTHORIZED(string.concat(symbol(), ': ', '!transfer'));
    if (from == to) revert FAILED((string.concat(symbol(), ': ', 'from == to')));
    super._transfer(from, to, amount);
  }

  function _validateHandler() internal view {
    if (!isHandler[msg.sender]) revert UNAUTHORIZED(string.concat(symbol(), ': ', '!handler'));
  }

  function setHandler(address _handler, bool _isActive) external onlyOwner {
    isHandler[_handler] = _isActive;
  }

  function setAllowUnsafeTransfer(address _handler, bool _isActive) external onlyOwner {
    allowUnsafeTransfer[_handler] = _isActive;
    emit UnsafeTransferAllowed(_handler, _isActive);
  }

  function setInPrivateTransferMode(bool _inPrivateTransferMode) external onlyOwner {
    inPrivateTransferMode = _inPrivateTransferMode;
  }

  function recoverErc20(IERC20 _erc20, uint _amount) external onlyOwner {
    IERC20(_erc20).transfer(owner(), _amount);
  }
}

