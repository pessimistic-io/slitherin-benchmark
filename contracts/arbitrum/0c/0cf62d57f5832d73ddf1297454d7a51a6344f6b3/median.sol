// SPDX-License-Identifier: GNU-3
pragma solidity ^0.8.13;

contract Median {
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
        require(wards[msg.sender] == 1, "Median/not-authorized");
        _;
    }

    uint128 val;
    uint32 public age;
    bytes32 public wat; // You want to change this every deploy
    uint256 public bar = 1;

    // orized oracles, set by an
    mapping(address => uint256) public orcl;

    // Whitelisted contracts, set by an
    mapping(address => uint256) public bud;

    // Mapping for at most 256 oracles
    mapping(uint8 => address) public slot;

    modifier toll() {
        require(bud[msg.sender] == 1, "Median/contract-not-whitelisted");
        _;
    }

    // --- Events ---
    event Rely(address indexed usr);
    event Deny(address indexed usr);

    event LogMedianPrice(uint256 val, uint256 age);

    //Set type of Oracle

    function read() external view toll returns (uint256) {
        require(val > 0, "Median/invalid-price-feed");
        return val;
    }

    function peek() external view toll returns (uint256, bool) {
        return (val, val > 0);
    }

    constructor(bytes32 _wat) public {
        wat = _wat;
        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

    function recover(uint256 val_, uint256 age_, uint8 v, bytes32 r, bytes32 s) internal view returns (address) {
        return ecrecover(
            keccak256(
                abi.encodePacked("\x19Ethereum Signed Message:\n32", keccak256(abi.encodePacked(val_, age_, wat)))
            ),
            v,
            r,
            s
        );
    }

    function poke(
        uint256[] calldata val_,
        uint256[] calldata age_,
        uint8[] calldata v,
        bytes32[] calldata r,
        bytes32[] calldata s
    ) external {
        require(val_.length == bar, "Median/bar-too-low");

        uint256 bloom = 0;
        uint256 last = 0;
        uint256 zzz = age;

        for (uint256 i = 0; i < val_.length; i++) {
            // Validate the values were signed by an orized oracle
            address signer = recover(val_[i], age_[i], v[i], r[i], s[i]);
            // Check that signer is an oracle
            require(orcl[signer] == 1, "Median/invalid-oracle");
            // Price feed age greater than last medianizer age
            require(age_[i] > zzz, "Median/stale-message");
            // Check for ordered values
            require(val_[i] >= last, "Median/messages-not-in-order");
            last = val_[i];
            // Bloom filter for signer uniqueness
            uint8 sl = uint8(uint256(uint160(signer)) >> 152);
            require((bloom >> sl) % 2 == 0, "Median/oracle-already-signed");
            bloom += uint256(2) ** sl;
        }

        val = uint128(val_[val_.length >> 1]);
        age = uint32(block.timestamp);

        emit LogMedianPrice(val, age);
    }

    function lift(address[] calldata a) external auth {
        for (uint256 i = 0; i < a.length; i++) {
            require(a[i] != address(0), "Median/no-oracle-0");
            uint8 s = uint8(uint256(uint160(a[i])) >> 152);
            require(slot[s] == address(0), "Median/signer-already-exists");
            orcl[a[i]] = 1;
            slot[s] = a[i];
        }
    }

    function drop(address[] calldata a) external auth {
        for (uint256 i = 0; i < a.length; i++) {
            orcl[a[i]] = 0;
            slot[uint8(uint256(uint160(a[i])) >> 152)] = address(0);
        }
    }

    function setBar(uint256 bar_) external auth {
        require(bar_ > 0, "Median/quorum-is-zero");
        require(bar_ % 2 != 0, "Median/quorum-not-odd-number");
        bar = bar_;
    }

    function kiss(address a) external auth {
        require(a != address(0), "Median/no-contract-0");
        bud[a] = 1;
    }

    function diss(address a) external auth {
        bud[a] = 0;
    }

    function kiss(address[] calldata a) external auth {
        for (uint256 i = 0; i < a.length; i++) {
            require(a[i] != address(0), "Median/no-contract-0");
            bud[a[i]] = 1;
        }
    }

    function diss(address[] calldata a) external auth {
        for (uint256 i = 0; i < a.length; i++) {
            bud[a[i]] = 0;
        }
    }
}

