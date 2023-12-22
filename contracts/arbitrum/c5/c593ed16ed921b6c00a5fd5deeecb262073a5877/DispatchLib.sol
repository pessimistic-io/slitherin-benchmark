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

import {IDispatcher} from "./IDispatcher.sol";
import { Account, END_USER_ACCOUNT } from "./Account.sol";
import "./ErrorsLib.sol";

library DispatchLib {
  function dispatch(
    address dispatcher,
		address source,
		address wallet,
		Account memory executor,
		bytes20 target,
		bytes4 selector
	) internal returns (address dispatchedTarget) {
    require(source != address(0), "DL: source required");
    require(wallet != address(0), "DL: wallet required");
    require(executor.accountType != END_USER_ACCOUNT, "DL: executor contract required");
    require(executor.accountAddress != address(0), "DL: executor required");
    require(target != bytes20(0), "DL: target required");
    require(selector != bytes4(0), "DL: selector required");

    // gas saving
    if (source == wallet) {
      source = address(0);
    }
    if (address(executor.accountAddress) == wallet) {
      executor.accountAddress = address(0);
    }
    if (address(target) == wallet) {
      target = bytes20(0);
    }

    dispatchedTarget = IDispatcher(dispatcher).dispatch(source, wallet, executor, target, selector);
    if (dispatchedTarget == address(0)) {
      revert ErrorsLib.NotDispatched(dispatcher, source, wallet, executor, target, selector);
    }
  }
}
