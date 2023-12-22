//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import "./IERC20Metadata.sol";

interface IConfig {
    function owner() external view returns (address);

    function getShares() external view returns (address);

    function getVAMM() external view returns (address);

    function getSequencer() external view returns (address);

    function getAuthenticate() external view returns (address);

    function acceptedToken() external view returns (IERC20Metadata);
}

