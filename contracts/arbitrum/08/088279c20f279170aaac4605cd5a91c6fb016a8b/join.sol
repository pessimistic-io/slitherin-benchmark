// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.13;
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

interface GemLike {
    function decimals() external view returns (uint256);

    function transfer(address, uint256) external returns (bool);

    function transferFrom(address, address, uint256) external returns (bool);
}

interface TokenLike {
    function mint(address, uint256) external;

    function burn(address, uint256) external;
}

interface VatLike {
    function slip(bytes32, address, int256) external;

    function move(address, address, uint256) external;
}

/*
    Here we provide *adapters* to connect the Vat to arbitrary external
    token implementations, creating a bounded context for the Vat. The
    adapters here are provided as working examples:

      - `GemJoin`: For well behaved ERC20 tokens, with simple transfer
                   semantics.

      - `ETHJoin`: For native Ether.

      - `ZarJoin`: For connecting internal zar balances to an external
                   `Token` implementation.

    In practice, adapter implementations will be varied and specific to
    individual collateral types, accounting for different transfer
    semantics and token standards.

    Adapters need to implement two basic methods:

      - `join`: enter collateral into the system
      - `exit`: remove collateral from the system*/

contract GemJoin {
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
        require(wards[msg.sender] == 1, "GemJoin/not-authorized");
        _;
    }

    VatLike public vat; // CDP Engine
    bytes32 public ilk; // Collateral Type
    GemLike public gem;
    uint256 public dec;
    uint256 public live; // Active Flag

    // Events
    event Rely(address indexed usr);
    event Deny(address indexed usr);
    event Join(address indexed usr, uint256 wad);
    event Exit(address indexed usr, uint256 wad);
    event Cage();

    constructor(address vat_, bytes32 ilk_, address gem_) public {
        wards[msg.sender] = 1;
        live = 1;
        vat = VatLike(vat_);
        ilk = ilk_;
        gem = GemLike(gem_);
        dec = gem.decimals();
        emit Rely(msg.sender);
    }

    function cage() external auth {
        live = 0;
        emit Cage();
    }

    function join(address usr, uint256 wad) external {
        require(live == 1, "GemJoin/not-live");
        require(int256(wad) >= 0, "GemJoin/overflow");
        vat.slip(ilk, usr, int256(wad));
        require(gem.transferFrom(msg.sender, address(this), wad), "GemJoin/failed-transfer");
        emit Join(usr, wad);
    }

    function exit(address usr, uint256 wad) external {
        require(wad <= 2 ** 255, "GemJoin/overflow");
        vat.slip(ilk, msg.sender, -int256(wad));
        require(gem.transfer(usr, wad), "GemJoin/failed-transfer");
        emit Exit(usr, wad);
    }
}

contract ZarJoin {
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
        require(wards[msg.sender] == 1, "DaiJoin/not-authorized");
        _;
    }

    VatLike public vat; // CDP Engine
    TokenLike public zar; // Stablecoin Token
    uint256 public live; // Active Flag

    // Events
    event Rely(address indexed usr);
    event Deny(address indexed usr);
    event Join(address indexed usr, uint256 wad);
    event Exit(address indexed usr, uint256 wad);
    event Cage();

    constructor(address vat_, address zar_) public {
        wards[msg.sender] = 1;
        live = 1;
        vat = VatLike(vat_);
        zar = TokenLike(zar_);
    }

    function cage() external auth {
        live = 0;
        emit Cage();
    }

    uint256 constant ONE = 10 ** 27;

    function mul(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require(y == 0 || (z = x * y) / y == x);
    }

    function join(address usr, uint256 wad) external {
        vat.move(address(this), usr, mul(ONE, wad));
        zar.burn(msg.sender, wad);
        emit Join(usr, wad);
    }

    function exit(address usr, uint256 wad) external {
        require(live == 1, "ZarJoin/not-live");
        vat.move(msg.sender, address(this), mul(ONE, wad));
        zar.mint(usr, wad);
        emit Exit(usr, wad);
    }
}

