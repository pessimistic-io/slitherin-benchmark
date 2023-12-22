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
pragma abicoder v1;

import "./IWETH.sol";
import "./ERC20Lib.sol";

/* interface for function calls from outside */
interface IETHLib {
	function transferETH(address payable to, uint value) external;
}

library ETHLib /* is IETHLib */ {
	/**
	 * @dev Return ethereum address
	 */
	address internal constant ethAddress = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

	/**
	 * Transfer ETH with unlimited gas: more robust, but no defence from reentrancy
	 */
	function transferETH(address payable to, uint value) internal returns (bytes memory response) {
		if (value == 0) {
			return "";
		}

		bool success;
		(success, response) = to.call{ value: value }("");
		require(success, "#ETHL: ETH transfer failed");
	}

  function wrap(address wethAddress, uint amount) internal {
    IWETH(wethAddress).deposit{value: amount}();
  }

  function unwrap(address wethAddress, uint amount) internal {
    ERC20Lib.ensureAllowance(wethAddress, wethAddress, amount);
    IWETH(wethAddress).withdraw(amount);
  }

  function convertWrapped(address fromWethAddress, address toWethAddress, uint amount) internal {
    if (fromWethAddress != toWethAddress) {
      unwrap(fromWethAddress, amount);
      wrap(toWethAddress, amount);
    }
  }
}

