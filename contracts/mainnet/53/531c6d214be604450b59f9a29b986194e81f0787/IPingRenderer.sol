// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "./PingAtts.sol";
import "./IValidatable.sol";

interface IPingRenderer is IValidatable {

    function render(
        uint256 tokenId,
        PingAtts memory atts,
        bool isSample
    )
        external
        view
        returns (string memory);

}

