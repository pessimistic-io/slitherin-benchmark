// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Copyright (C) 2017 DappHub, LLC
// Copyright (C) 2022 Dai Foundation
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

interface AuthorityLike {
    function canCall(address src, address dst, bytes4 sig) external view returns (bool);
}

interface IDssProxy {
    function owner() external view returns (address owner_);
    function authority() external view returns (address authority_);
    function setOwner(address owner_) external;
    function setAuthority(address authority_) external;
    function execute(address target_, bytes memory data_) external payable returns (bytes memory response);
}

