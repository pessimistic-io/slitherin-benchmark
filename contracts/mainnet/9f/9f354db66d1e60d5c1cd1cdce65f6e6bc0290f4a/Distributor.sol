// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { BitMaps } from "./BitMaps.sol";
import { IAccessControl } from "./IAccessControl.sol";
import { IERC721Enumerable } from "./IERC721Enumerable.sol";

import { ReentrancyGuard } from "./ReentrancyGuard.sol";
import { SafeToken } from "./SafeToken.sol";

import { IERC20 } from "./IERC20.sol";


contract Distributor is ReentrancyGuard
{
  using SafeToken for IERC20;
  using BitMaps for BitMaps.BitMap;


  address private constant _GLOVE = 0x70c5f366dB60A2a0C59C4C24754803Ee47Ed7284;
  address private constant _LOBS = 0x026224A2940bFE258D0dbE947919B62fE321F042;

  uint256 private constant _CAP = 1066e18; // LOBS + 1

  uint256 private immutable _DEADLINE;


  BitMaps.BitMap private _validated;

  bool private _closed;
  uint256 private _distributed;

  mapping(address => bool) private _lobster;
  mapping(address => uint) private _lobsters;


  event Claim(address lobster);
  event Collect(address lobster);


  constructor ()
  {
    _DEADLINE = block.timestamp + 70 minutes;
  }


  function closed () external view returns (bool)
  {
    return _closed;
  }

  function deadline () external view returns (uint256)
  {
    return _DEADLINE;
  }

  function remaining () external view returns (uint256)
  {
    return _CAP - _distributed;
  }


  function claim () external nonReentrant
  {
    require(!_lobster[msg.sender], "lobster");
    require(tx.origin == msg.sender, "!seabug");
    require(block.timestamp < _DEADLINE && _distributed < _CAP, "closed");


    uint256 balance = IERC721Enumerable(_LOBS).balanceOf(msg.sender);

    require(balance >= 2, "shrimp");


    uint lob;
    bool lobstered;

    for (uint256 i; i < balance;)
    {
      lob = IERC721Enumerable(_LOBS).tokenOfOwnerByIndex(msg.sender, i);


      if (_validated.get(lob))
      {
        lobstered = true;
      }


      _validated.set(lob);


      unchecked { i++; }
    }


    if (!lobstered)
    {
      _distributed += 2e18;
      _lobsters[msg.sender] = 2e18;

      IERC20(_GLOVE).mint(address(this), 2e18);
    }


    _lobster[msg.sender] = true;


    emit Claim(msg.sender);
  }


  function lobster (address account) external view returns (bool)
  {
    return _lobster[account];
  }


  function _cleanup () private
  {
    if (!_closed)
    {
      _closed = true;

      IAccessControl(_GLOVE).renounceRole(0xbe74a168a238bf2df7daa27dd5487ac84cb89ae44fd7e7d1e4b6397bfe51dcb8, address(this));
    }
  }

  function collect () external nonReentrant
  {
    require(_lobster[msg.sender], "!lobster");
    require(_distributed >= _CAP || block.timestamp > _DEADLINE, "!closed");


    _cleanup();

    _lobster[msg.sender] = false;

    IERC20(_GLOVE).safeTransfer(msg.sender, _lobsters[msg.sender]);


    emit Collect(msg.sender);
  }
}

