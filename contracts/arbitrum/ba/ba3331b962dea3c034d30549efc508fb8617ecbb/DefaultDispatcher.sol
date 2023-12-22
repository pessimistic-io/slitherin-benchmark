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
import "./ISmartWallet.sol";
import "./ManagedDispatcher.sol";
import { Account, OWNED_SMART_WALLET_ACCOUNT, END_USER_ACCOUNT } from "./Account.sol";
// import "hardhat/console.sol";

contract DefaultDispatcher is ManagedDispatcher {
  function dispatch(
		address source,
    address wallet,
    Account calldata executor,
		bytes20 target,
		bytes4 selector
	) external view override returns (address dispatchedTarget) {    
    if (target == bytes20(0)) {
      // fallback calls: lookup by signature only and no authorization 
      if (executor.accountType != OWNED_SMART_WALLET_ACCOUNT) {
        // no calls from third-party executors to wallet
        return address(0);
      }
    } else {
      bool authorized = source == address(0) || source == ISmartWallet(wallet).owner();

      if (!authorized) {
        return address(0);
      }
    } 

    return getTargeOrDefault(executor.accountType, target, selector);
	}
}

