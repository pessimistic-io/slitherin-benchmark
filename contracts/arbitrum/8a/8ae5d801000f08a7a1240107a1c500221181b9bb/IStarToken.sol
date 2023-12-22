// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "./IERC20.sol";

interface IStarToken is IERC20 {
    // --- Events ---

    function mintFromWhitelistedContract(uint256 _amount) external;

    function burnFromWhitelistedContract(uint256 _amount) external;

    function sendToPool(
        address _sender,
        address poolAddress,
        uint256 _amount
    ) external;

    function returnFromPool(
        address poolAddress,
        address user,
        uint256 _amount
    ) external;
}


