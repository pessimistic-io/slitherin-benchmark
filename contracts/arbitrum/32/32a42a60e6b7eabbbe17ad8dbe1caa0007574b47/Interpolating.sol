// SPDX-License-Identifier: MIT

import { SafeMath } from "./SafeMath.sol";

pragma solidity 0.8.19;
pragma experimental ABIEncoderV2;

contract Interpolating {
    using SafeMath for uint256;

    struct Interpolation {
        uint256 startOffset;
        uint256 endOffset;
        uint256 startScale;
        uint256 endScale;
    }
    uint256 public constant INTERPOLATION_DIVISOR = 1000000;


    function lerp(uint256 startOffset, uint256 endOffset, uint256 startScale, uint256 endScale, uint256 current) public pure returns (uint256) {
        if (endOffset <= startOffset) {
            // If the end is less than or equal to the start, then the value is always endValue.
            return endScale;
        }

        if (current <= startOffset) {
            // If the current value is less than or equal to the start, then the value is always startValue.
            return startScale;
        }

        if (current >= endOffset) {
            // If the current value is greater than or equal to the end, then the value is always endValue.
            return endScale;
        }

        uint256 range = endOffset.sub(startOffset);
        if (endScale > startScale) {
            // normal increasing value
            return current.sub(startOffset).mul(endScale.sub(startScale)).div(range).add(startScale);
        } else {
            // decreasing value requires different calculation
            return endOffset.sub(current).mul(startScale.sub(endScale)).div(range).add(endScale);
        }
    }

    function lerpValue(Interpolation memory data, uint256 current, uint256 value) public pure returns (uint256) {
        return lerp(data.startOffset, data.endOffset, data.startScale, data.endScale, current).mul(value).div(INTERPOLATION_DIVISOR);
    }
}
