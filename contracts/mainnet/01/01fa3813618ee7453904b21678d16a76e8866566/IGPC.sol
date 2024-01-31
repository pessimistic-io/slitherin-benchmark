//SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import "./ERC1155_IERC1155.sol";

interface IGPC is IERC1155 {
    function burn(
        address _owner,
        uint256 _id,
        uint256 _amount
    ) external;
}

