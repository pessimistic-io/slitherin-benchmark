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

import { IERC20Metadata } from "./IERC20Metadata.sol";
import { SafeERC20 } from "./SafeERC20.sol";
import "./IERC721Receiver.sol";

/* interface for function calls from outside */
interface IERC20Lib {
	function safeApproveBatch(address[] calldata tokens, address to, uint[] calldata values) external;

	function safeTransferBatch(address[] calldata tokens, address to, uint[] calldata values) external;

  function safeTransferFromBatch(address[] calldata tokens, address from, address to, uint[] calldata amounts) external;

  function safeApprove(address token, address to, uint value) external;

  function safeTransfer(address token, address to, uint value) external;

  function safeTransferFrom(address token, address from, address to, uint value) external;
}

library ERC20Lib /* is IERC20Lib */ {
	function safeApproveBatch(address[] calldata tokens, address to, uint[] calldata values) external {
		require(tokens.length == values.length, "#ERC20L: Input lenghts mismatch");
    for (uint currentToken = 0; currentToken < tokens.length; currentToken++) {
			safeApprove(tokens[currentToken], to, values[currentToken]);
		}
	}

	function safeTransferBatch(address[] calldata tokens, address to, uint[] calldata values) external {
		require(tokens.length == values.length, "#ERC20L: Input lenghts mismatch");
    for (uint currentToken = 0; currentToken < tokens.length; currentToken++) {
			safeTransfer(tokens[currentToken], to, values[currentToken]);
		}
	}

  function safeTransferFromBatch(address[] calldata tokens, address from, address to, uint[] calldata values) external {
		require(tokens.length == values.length, "#ERC20L: Input lenghts mismatch");
    for (uint currentToken = 0; currentToken < tokens.length; currentToken++) {
			safeTransferFrom(tokens[currentToken], from, to, values[currentToken]);
		}
	}

	function safeApprove(address token, address to, uint value) public {
    SafeERC20.safeApprove(IERC20Metadata(token), to, value);
	}

  function ensureAllowance(address token, address to, uint value) public {
    uint allowance = IERC20Metadata(token).allowance(address(this), to);
    if (allowance >= value) {
      return;
    } else {
      SafeERC20.safeIncreaseAllowance(IERC20Metadata(token), to, value - allowance);
    }
	}

	function safeTransfer(address token, address to, uint value) public {
		if (value == 0) {
			return;
		}

		value = value == type(uint).max ? IERC20Metadata(token).balanceOf(address(this)) : value;
    SafeERC20.safeTransfer(IERC20Metadata(token), to, value);
    // return value;
	}

	function safeTransferFrom(address token, address from, address to, uint value) public {
		if (value == 0) {
			return;
		}

		value = value == type(uint).max ? IERC20Metadata(token).balanceOf(from) : value;
    SafeERC20.safeTransferFrom(IERC20Metadata(token), from, to, value);
    // return value;
	}
}

