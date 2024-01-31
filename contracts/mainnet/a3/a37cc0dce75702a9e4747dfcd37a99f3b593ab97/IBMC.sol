//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "./IERC721.sol";
import "./IERC721Metadata.sol";
import "./IValidator.sol";
import "./IKillswitch.sol";

interface IBMC is IERC721, IERC721Metadata, IValidator, IKillswitch {
    function setBaseUri(string memory baseUri) external;
    function setERC20PriceStrategy(address erc20Contract, address priceStrategyAddress) external;
    function setSalesStartAt(uint256 timestamp) external;

    function totalSupply() external view returns (uint256);
    function maxSupply() external view returns (uint256);
    function getERC20Price(address erc20Contract, uint256 tokenNum) external view returns (uint256);
    function getSalesStartAt() external view returns (uint256);

    function mintForERC20(address erc20Contract, uint256 amount) external;

    function validatorMintNew(address mintFor, uint256 amount) external;
    function validatorMint(address mintFor, uint256 tokenId) external;
    function validatorBurn(uint256 tokenId) external;

    function withdraw() external;
}

