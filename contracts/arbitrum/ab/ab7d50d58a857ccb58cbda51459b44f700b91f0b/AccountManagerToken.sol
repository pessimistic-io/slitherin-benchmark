/**
 * SPDX-License-Identifier: GPL-3.0-or-later
 * DeDeLend
 * Copyright (C) 2022 DeDeLend
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 **/

pragma solidity 0.8.6;

import "./ERC721.sol";
import "./Ownable.sol";

contract AccountManagerToken is
    ERC721("Tokenized GMX Positions", "TGP"),
    Ownable
{
    address public accountManager;
    uint256 public tokenId = 0;

    constructor() {}

    function setAccountManager(address value) external onlyOwner {
        accountManager = value;
    }

    function mint(address to, uint256 id) external {
        require(msg.sender == accountManager, "caller is not the accountManager");
        _safeMint(to, id);
    }

    function addTokenId(uint256 value) external {
        require(msg.sender == accountManager, "caller is not the accountManager");
        tokenId += value; 
    }
}

