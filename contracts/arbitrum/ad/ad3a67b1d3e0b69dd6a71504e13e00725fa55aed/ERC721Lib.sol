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

import "./IERC721.sol";
import "./IERC721Receiver.sol";

/* interface for function calls from outside */
interface IERC721Lib {
  function approveBatch(address token, address to, uint[] calldata tokenIds) external;

  function transferFromBatch(address token, address from, address to, uint[] calldata tokenIds) external;

  function safeTransferFromBatch(address token, address from, address to, uint[] calldata tokenIds, bytes calldata data) external;

  function approve(address token, address to, uint tokenId) external;

  function setApprovalForAll(address token, address operator, bool approved) external;

  function transferFrom(address token, address from, address to, uint tokenId) external;

  function safeTransferFrom(address token, address from, address to, uint tokenId, bytes calldata data) external;
}

/**
 * interface for methods directly callable from smart wallet 
 */
interface IERC721LibGlobal is IERC721Receiver {
}

library ERC721Lib /* is IERC721Lib, IERC721LibGlobal */ {
  function approveBatch(address token, address to, uint[] calldata tokenIds) external {
    for (uint currentTokenId = 0; currentTokenId < tokenIds.length; currentTokenId++) {
      IERC721(token).approve(to, tokenIds[currentTokenId]);
    }
	}

  function transferFromBatch(address token, address from, address to, uint[] calldata tokenIds) external {
    for (uint currentTokenId = 0; currentTokenId < tokenIds.length; currentTokenId++) {
      IERC721(token).transferFrom(from, to, tokenIds[currentTokenId]);
    } 
	}

  function safeTransferFromBatch(address token, address from, address to, uint[] calldata tokenIds, bytes calldata data) external {
    for (uint currentTokenId = 0; currentTokenId < tokenIds.length; currentTokenId++) {
      IERC721(token).safeTransferFrom(from, to, tokenIds[currentTokenId], data);
    }
	}

	function approve(address token, address to, uint tokenId) external {
    IERC721(token).approve(to, tokenId);
	}

  function setApprovalForAll(address token, address operator, bool approved) external {
    IERC721(token).setApprovalForAll(operator, approved);
	}

	function transferFrom(address token, address from, address to, uint tokenId) external {
    IERC721(token).transferFrom(from, to, tokenId);
	}

  function safeTransferFrom(address token, address from, address to, uint tokenId, bytes calldata data) external {
    IERC721(token).safeTransferFrom(from, to, tokenId, data);
	}

  function onERC721Received(
      address,
      address,
      uint256,
      bytes calldata
  ) external pure returns (bytes4) {
    return IERC721Receiver.onERC721Received.selector;
  }
}

