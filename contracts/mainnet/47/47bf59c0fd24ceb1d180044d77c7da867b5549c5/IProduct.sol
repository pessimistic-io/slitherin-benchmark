// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IProduct {
    
    // get product's owner
    function getProdOwner(uint256 prodId) external view returns(address);

    // get product's total supply
    function getMaxProdId() external view returns(uint256);

    // update product's score
    function updateProdScore(uint256 prodId, bool ifSuccess) external returns(bool);

    // get product's block status
    function isProductBlocked(uint256 prodId) external view returns(bool);
}
