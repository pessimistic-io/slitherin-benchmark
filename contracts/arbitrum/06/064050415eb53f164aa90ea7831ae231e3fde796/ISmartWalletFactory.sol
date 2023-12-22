
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

interface ISmartWalletFactory {
  function smartWalletImplementation() external view returns (address);
  function dispatcher() external view returns (address);

  function findNewSmartWalletAddress(address user, uint96 initialSeed) external view returns (address smartWallet, uint96 seed);
  function build(address creator, uint96 seed) external returns (address smartWallet);
  function buildAndExec(address creator, uint96 seed, bytes20 target, bytes calldata data) external payable returns (bytes memory response);
  
  // new implementations of ISmartWalletFactory should be able to return implementation of old wallets
  function getWalletImplementation(address smartWallet) external view returns (address impl);

    event SmartWalletCreated(address indexed smartWallet, address indexed creator, uint96 indexed seed);
}


