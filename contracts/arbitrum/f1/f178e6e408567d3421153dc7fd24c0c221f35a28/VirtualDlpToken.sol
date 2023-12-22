// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.20;

import "./ERC20.sol";
import "./Ownable2Step.sol";
import "./EnumerableSet.sol";

import { ITokenMinter, IErrors } from "./Common.sol";

interface IVirtualDlpToken is IErrors {
  event OperatorUpdated(address newOperator, address operator);
}

contract VirtualDlpToken is IVirtualDlpToken, ITokenMinter, ERC20, Ownable2Step {
  using EnumerableSet for EnumerableSet.AddressSet;

  EnumerableSet.AddressSet private operators;

  constructor() ERC20('Virtual dLP', 'v-dLP') Ownable(msg.sender) {}

  function mint(address _to, uint256 _amount) external {
    _mint(_to, _amount);
  }

  function burn(address _from, uint256 _amount) external {
    _burn(_from, _amount);
  }

  function _update(address from, address to, uint256 value) internal override {
    if (!operators.contains(msg.sender)) revert UNAUTHORIZED();
    super._update(from, to, value);
  }

  function getOperators() public view returns (address[] memory) {
    return operators.values();
  }

  /** OWNER FUNCTIONS */
  function addOperator(address _newOperator) external onlyOwner {
    bool added = operators.add(_newOperator);
    emit OperatorUpdated(_newOperator, address(0));

    if (!added) {
      revert FAILED('VirtualDlpToken: operator exists');
    }
  }

  function removeOperator(address _existingOperator) external onlyOwner {
    bool removed = operators.remove(_existingOperator);
    emit OperatorUpdated(address(0), _existingOperator);

    if (!removed) {
      revert FAILED('VirtualDlpToken: operator !exists');
    }
  }
}

