// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

interface IZLKDiscountReader {
    function getZLKDiscount(address user) external view returns (uint256 discount, uint256 basis);
}

