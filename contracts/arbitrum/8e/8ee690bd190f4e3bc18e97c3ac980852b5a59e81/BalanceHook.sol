// SPDX-License-Identifier: AGPL-3.0

import "./ICharacter.sol";
import "./IXferHook.sol";

pragma solidity ^0.8.0;

contract BalanceHook is IXferHook {
  ICharacter private _character;

  mapping(address => uint256[]) private _balance;
  mapping(uint256 => uint256) private _idIndex;


  function getTokens(address player) public view returns (uint256[] memory) {
    return _balance[player];
  }

  function xferHook(
    address from,
    address to,
    uint256 id
  ) external override {
    if(from == address(0)) {
      _balance[to].push(id);
      _idIndex[id] = _balance[to].length - 1;
    } else if(to == address(0)) {
      uint256 index = _idIndex[id];
      _balance[from][index] = _balance[from][_balance[from].length - 1];
    } else {
      _balance[to].push(id);
      _idIndex[id] = _balance[to].length - 1;
      uint256 index = _idIndex[id];
      _balance[from][index] = _balance[from][_balance[from].length - 1];
    }
  }
}

