//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.14;

import "./MathUpgradeable.sol";

library MathLib {
    uint256 public constant WAD = 1e18;

    function mulWadDown(uint256 a, uint256 b) internal pure returns (uint256 c) {
        c = a * b;
        unchecked {
            c /= WAD;
        }
    }

    function divWadDown(uint256 a, uint256 b) internal pure returns (uint256 c) {
        c = a * WAD;
        unchecked {
            c /= b;
        }
    }

    function mulWadUp(uint256 a, uint256 b) internal pure returns (uint256) {
        return mulArbUp(a, b, WAD);
    }

    function divWadUp(uint256 a, uint256 b) internal pure returns (uint256) {
        return divArbUp(a, b, WAD);
    }

    function mulArbUp(
        uint256 a,
        uint256 b,
        uint256 scale
    ) internal pure returns (uint256) {
        return MathUpgradeable.ceilDiv(a * b, scale);
    }

    function divArbUp(
        uint256 a,
        uint256 b,
        uint256 scale
    ) internal pure returns (uint256) {
        return MathUpgradeable.ceilDiv(a * scale, b);
    }
}

