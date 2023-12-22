// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import "./console.sol";

library Log {

    function log(string memory name) internal view {
        console.log('\n==================== %s ====================', name);
    }

    function log(string memory value, string memory name) internal view {
        console.log('%s: %s', name, value);
    }

    function log(uint256 value, string memory name) internal view {
        console.log('%s: %s', name, value);
    }

    function log(int256 value, string memory name) internal view {
        if (value >= 0) console.log('%s: %s', name, uint256(value));
        else console.log('%s: -%s', name, uint256(-value));
    }

    function log18(uint256 value, string memory name) internal view {
        console.log('%s: %s.%s', name, value / 1e18, value % 1e18);
    }

    function log18(int256 value, string memory name) internal view {
        if (value >= 0) {
            console.log('%s: %s.%s', name, uint256(value) / 1e18, uint256(value) % 1e18);
        } else {
            console.log('%s: -%s.%s', name, uint256(-value) / 1e18, uint256(-value) % 1e18);
        }
    }

    function log(address value, string memory name) internal view {
        console.log('%s: %s', name, value);
    }

    function log(bool value, string memory name) internal view {
        console.log('%s: %s', name, value);
    }

    function log(bytes32 value, string memory name) internal view {
        console.log('%s:', name);
        console.logBytes32(value);
    }

    function log(bytes memory value, string memory name) internal view {
        console.log('%s:', name);
        console.logBytes(value);
    }

}

