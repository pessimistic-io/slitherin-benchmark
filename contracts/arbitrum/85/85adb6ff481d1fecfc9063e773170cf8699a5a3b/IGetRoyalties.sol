// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./IERC165.sol";

interface IGetRoyalties is IERC165 {
    function getFeeRecipients(uint256 _id)
        external
        view
        returns (address payable[] memory);

    function getFeeBps(uint256 _id) external view returns (uint16[] memory);
}

