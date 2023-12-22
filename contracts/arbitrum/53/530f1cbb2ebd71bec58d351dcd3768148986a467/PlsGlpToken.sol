// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.9;

import "./ERC20.sol";
import "./Ownable.sol";

contract PlsGlpToken is ERC20, Ownable {
  address public operator;
  bool public inPrivateTransferMode;
  mapping(address => bool) public isHandler;

  constructor() ERC20('Plutus Staked GLP', 'plsGLP') {
    inPrivateTransferMode = true;
  }

  function mint(address _to, uint256 _amount) external {
    if (msg.sender != operator) revert UNAUTHORIZED();
    _mint(_to, _amount);
  }

  function burn(address _from, uint256 _amount) external {
    if (msg.sender != operator) revert UNAUTHORIZED();
    _burn(_from, _amount);
  }

  /** OVERRIDES */

  ///@dev plsGLP transfers are permissioned
  function _transfer(
    address from,
    address to,
    uint256 amount
  ) internal override {
    if (isHandler[msg.sender] || !inPrivateTransferMode) {
      super._transfer(from, to, amount);
    } else {
      revert UNAUTHORIZED();
    }
  }

  /** OWNER FUNCTIONS */
  function setOperator(address _operator) external onlyOwner {
    emit OperatorChanged(_operator, operator);
    operator = _operator;
  }

  function setInPrivateTransferMode(bool _inPrivateTransferMode) external onlyOwner {
    inPrivateTransferMode = _inPrivateTransferMode;
    emit InPrivateTransferMode(_inPrivateTransferMode);
  }

  function updateHandler(address _handler, bool _isActive) external onlyOwner {
    isHandler[_handler] = _isActive;
    emit HandlerUpdated(_handler, _isActive);
  }

  event HandlerUpdated(address indexed _newHandler, bool _isActive);
  event OperatorChanged(address indexed _new, address _old);
  event InPrivateTransferMode(bool _isInPrivateTransferMode);

  error UNAUTHORIZED();
}

