// SPDX-License-Identifier: GNU-3
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

pragma solidity ^0.8.13;

import "./value.sol";

contract OSM {
    // --- Auth ---
    mapping(address => uint256) public wards;

    function rely(address usr) external auth {
        wards[usr] = 1;
        emit Rely(usr);
    }

    function deny(address usr) external auth {
        wards[usr] = 0;
        emit Deny(usr);
    }

    modifier auth() {
        require(wards[msg.sender] == 1, "OSM/not-authorized");
        _;
    }

    // --- Stop ---
    uint256 public stopped;

    modifier stoppable() {
        require(stopped == 0, "OSM/is-stopped");
        _;
    }

    address public src;
    uint16 constant ONE_HOUR = uint16(3600);
    uint16 public hop = ONE_HOUR;
    uint64 public zzz;

    struct Feed {
        uint128 val;
        uint128 has;
    }

    Feed cur;
    Feed nxt;

    // Whitelisted contracts
    mapping(address => uint256) public bud;

    modifier toll() {
        require(bud[msg.sender] == 1, "OSM/contract-not-whitelisted");
        _;
    }

    // --- Events ---
    event Rely(address indexed usr);
    event Deny(address indexed usr);

    event LogValue(bytes32 val);

    constructor(address src_) public {
        wards[msg.sender] = 1;
        src = src_;
    }

    function stop() external auth {
        stopped = 1;
    }

    function start() external auth {
        stopped = 0;
    }

    function change(address src_) external auth {
        src = src_;
    }

    function era() internal view returns (uint256) {
        return block.timestamp;
    }

    function prev(uint256 ts) internal view returns (uint64) {
        require(hop != 0, "OSM/hop-is-zero");
        return uint64(ts - (ts % hop));
    }

    function step(uint16 ts) external auth {
        require(ts > 0, "OSM/ts-is-zero");
        hop = ts;
    }

    function void() external auth {
        cur = nxt = Feed(0, 0);
        stopped = 1;
    }

    function pass() public view returns (bool ok) {
        return era() >= zzz + hop;
    }

    function poke() external stoppable {
        require(pass(), "OSM/not-passed");
        (bytes32 wut, bool ok) = Value(src).peek();
        if (ok) {
            cur = nxt;
            nxt = Feed(uint128(uint256(wut)), 1);
            zzz = prev(era());
            emit LogValue(bytes32(uint256(cur.val)));
        }
    }

    function peek() external view toll returns (bytes32, bool) {
        return (bytes32(uint256(cur.val)), cur.has == 1);
    }

    function peep() external view toll returns (bytes32, bool) {
        return (bytes32(uint256(nxt.val)), nxt.has == 1);
    }

    function read() external view toll returns (bytes32) {
        require(cur.has == 1, "OSM/no-current-value");
        return (bytes32(uint256(cur.val)));
    }

    function kiss(address a) external auth {
        require(a != address(0), "OSM/no-contract-0");
        bud[a] = 1;
    }

    function diss(address a) external auth {
        bud[a] = 0;
    }

    function kiss(address[] calldata a) external auth {
        for (uint256 i = 0; i < a.length; i++) {
            require(a[i] != address(0), "OSM/no-contract-0");
            bud[a[i]] = 1;
        }
    }

    function diss(address[] calldata a) external auth {
        for (uint256 i = 0; i < a.length; i++) {
            bud[a[i]] = 0;
        }
    }
}

