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
import { Account, OWNED_SMART_WALLET_ACCOUNT, END_USER_ACCOUNT } from "./Account.sol";

interface IDispatcher {
	function dispatch(
		address source,
		address wallet,
		Account calldata executor,
		bytes20 target,
		bytes4 selector
	) external returns (address dispatchedTarget);
}

