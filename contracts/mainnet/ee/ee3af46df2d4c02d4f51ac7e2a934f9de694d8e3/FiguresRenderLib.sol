// SPDX-License-Identifier: MIT

pragma solidity ^0.8.1;

import "./Strings.sol";
import "./Math.sol";

library FiguresRenderLib {
    function _concat(string memory a, string memory b)
        private
        pure
        returns (string memory)
    {
        return string(abi.encodePacked(a, b));
    }

    function _generateRect(
        uint256 x,
        uint256 y,
        uint256 width,
        uint256 height,
        string memory color,
        string memory style
    ) public pure returns (string memory) {
        string memory s = "";
        s = _concat(s, "<rect x='");
        s = _concat(s, Strings.toString(x));
        s = _concat(s, "' y='");
        s = _concat(s, Strings.toString(y));
        s = _concat(s, "' width='");
        s = _concat(s, Strings.toString(width));
        s = _concat(s, "' height='");
        s = _concat(s, Strings.toString(height));
        s = _concat(s, "' style='fill:rgb(");
        s = _concat(s, color);
        s = _concat(s, "); ");
        s = _concat(s, style);
        s = _concat(s, "'/>");
        return s;
    }

    function _generatePixelSVG(
        uint256 x,
        uint256 y,
        uint256 factor,
        string memory color
    ) public pure returns (string memory) {
        string memory s = "";
        s = _concat(s, "<rect x='");
        s = _concat(s, Strings.toString(x));
        s = _concat(s, "' y='");
        s = _concat(s, Strings.toString(y));
        s = _concat(s, "' width='");
        s = _concat(s, Strings.toString(factor));
        s = _concat(s, "' height='");
        s = _concat(s, Strings.toString(factor));
        s = _concat(s, "' style='fill:rgb(");
        s = _concat(s, color);
        s = _concat(s, "); mix-blend-mode: multiply;'/>");
        return s;
    }
}

