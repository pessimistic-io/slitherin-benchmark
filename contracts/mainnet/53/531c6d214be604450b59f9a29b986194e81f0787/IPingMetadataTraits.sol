// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "./PingAtts.sol";
import "./IValidatable.sol";

interface IPingMetadataTraits is IValidatable {

    function getTraits(PingAtts memory atts) external view returns (string memory);

}

