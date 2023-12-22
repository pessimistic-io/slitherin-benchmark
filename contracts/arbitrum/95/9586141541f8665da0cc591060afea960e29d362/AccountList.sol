// SPDX-License-Identifier: AGPL-3.0
pragma solidity =0.8.7;

import "./SafeOwnable.sol";
import "./IAccountList.sol";

contract AccountList is IAccountList, SafeOwnable {
  uint256 private _resetIndex;
  mapping(uint256 => mapping(address => bool))
    private _resetIndexToAccountToIncluded;

  constructor() {}

  function set(address[] calldata accounts, bool[] calldata included)
    external
    override
    onlyOwner
  {
    require(accounts.length == included.length, "Array length mismatch");
    uint256 arrayLength = accounts.length;
    for (uint256 i; i < arrayLength; ) {
      _resetIndexToAccountToIncluded[_resetIndex][accounts[i]] = included[i];
      unchecked {
        ++i;
      }
    }
  }

  function reset(address[] calldata includedAccounts)
    external
    override
    onlyOwner
  {
    _resetIndex++;
    uint256 arrayLength = includedAccounts.length;
    for (uint256 i; i < arrayLength; ) {
      _resetIndexToAccountToIncluded[_resetIndex][includedAccounts[i]] = true;
      unchecked {
        ++i;
      }
    }
  }

  function isIncluded(address account) external view override returns (bool) {
    return _resetIndexToAccountToIncluded[_resetIndex][account];
  }
}

