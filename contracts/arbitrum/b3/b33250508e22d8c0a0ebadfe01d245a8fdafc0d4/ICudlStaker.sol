//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

interface ICudlStaker {
    function balanceByPool(uint256 pool, address user)
        external
        view
        returns (uint256);

    function earned(address account) external view returns (uint256);

    function burnPoints(address _user, uint256 amount) external;
}

