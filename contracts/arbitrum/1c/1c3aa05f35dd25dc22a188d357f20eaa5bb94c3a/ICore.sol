//SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

interface ICore {
    function withdraw(uint256 _amount) external;

    function withdrawERC20(
        address _tokenAddress,
        uint256 _amount
    ) external;
}

