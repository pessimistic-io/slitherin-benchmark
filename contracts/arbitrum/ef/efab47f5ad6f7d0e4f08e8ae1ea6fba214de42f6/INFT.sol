// SPDX-License-Identifier: MIT
pragma solidity =0.8.15;

interface INFT {
    event PriceChange(address indexed sender,uint256 tokenId,uint256 price,uint256 prePrice);

    function operatorApprovalForAll(address owner) external ;
    function prices(uint256 tokenId) external returns(uint256 price);
    function setPrice(uint256 tokenId,uint256 price) external;
    function setOperator(address _operator) external;
    // function mint(address to) external returns(uint256 tokenId);
    function currentId() external view returns (uint256) ;
}

