
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Copyright (C) 2023 VALK
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

pragma solidity ^0.8.18;

interface ISmartWallet {
  function exec(
    bytes20 target, // name or address of target script 
    bytes memory data
  ) external payable returns (bytes memory response);

  event SW_Exec(address indexed sender, bytes4 indexed selector, address indexed dispatchedTarget, bytes20 target, uint value);
  event SW_ExecDirect(address indexed sender, bytes4 indexed selector, address indexed dispatchedTarget, uint value);
  event SW_Fallback(address indexed sender, bytes4 indexed selector, uint value);
  event SW_SetOwner(address indexed owner);
  event SW_SetDispatcher(address indexed dispatcher);

  function owner() external view returns (address);
  function dispatcher() external view returns (address);
  function setDispatcher(address _dispatcher) external;
  function registry() external view returns (address);
}


