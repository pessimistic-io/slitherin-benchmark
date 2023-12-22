pragma solidity >=0.8.19;

import {UD60x18, toUD60x18, ud} from "./UD60x18.sol";

library Time {
    using {toUD60x18} for uint256;

    uint256 public constant SECONDS_IN_YEAR = 31536000;

    /// @dev Returns the block timestamp truncated to 32 bits, checking for overflow.
    function blockTimestampTruncated() internal view returns (uint32) {
        return timestampAsUint32(block.timestamp);
    }

    function timestampAsUint32(uint256 _timestamp) internal pure returns (uint32 timestamp) {
        require((timestamp = uint32(_timestamp)) == _timestamp, "TSOFLOW");
    }

    function timeDeltaAnnualized(uint32 timestamp) internal view returns (UD60x18 timeDeltaAnnualized) {
        if (timestamp > blockTimestampTruncated()) {
            timeDeltaAnnualized = (uint256(timestamp) - block.timestamp).toUD60x18().div(SECONDS_IN_YEAR.toUD60x18());
        }
    }
}

