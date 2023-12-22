// SPDX-License-Identifier: AGPL-3.0
pragma solidity =0.8.7;

import {SafeOwnable} from "./SafeOwnable.sol";
import {IAccountList} from "./IAccountList.sol";
import {EnumerableMap} from "./EnumerableMap.sol";

contract AccountList is IAccountList, SafeOwnable {
  using EnumerableMap for EnumerableMap.AddressToUintMap;

  uint256 private _resetIndex;
  mapping(uint256 => EnumerableMap.AddressToUintMap)
    private _resetIndexToAccountToIncluded;

  constructor() {}

  function set(address[] calldata accounts, bool[] calldata included)
    external
    override
    onlyOwner
  {
    if (accounts.length != included.length) revert ArrayLengthMismatch();
    uint256 arrayLength = accounts.length;
    for (uint256 i; i < arrayLength; ) {
      uint256 inclusionUint = included[i] ? 1 : 0;
      _resetIndexToAccountToIncluded[_resetIndex].set(
        accounts[i],
        inclusionUint
      );
      unchecked {
        ++i;
      }
    }
    emit AccountListChange(accounts, included);
  }

  function reset() external override onlyOwner {
    _resetIndex++;
    emit AccountListReset();
  }

  function isIncluded(address account) external view override returns (bool) {
    (, uint256 inclusionUint) = _resetIndexToAccountToIncluded[_resetIndex]
      .tryGet(account);
    return inclusionUint != 0;
  }

  function getAccountAndInclusion(uint256 index)
    external
    view
    override
    returns (address, bool)
  {
    (address account, uint256 inclusionUint) = _resetIndexToAccountToIncluded[
      _resetIndex
    ].at(index);
    return (account, inclusionUint != 0);
  }

  function getAccountListLength() external view override returns (uint256) {
    return _resetIndexToAccountToIncluded[_resetIndex].length();
  }
}

