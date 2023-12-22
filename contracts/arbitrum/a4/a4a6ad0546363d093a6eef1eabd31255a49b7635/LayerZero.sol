// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./ONFT721Core.sol";
import "./IONFT721Core.sol";
import "./Multicall.sol";

contract LayerZero is IONFT721Core, ONFT721Core, Multicall {

    address public nft;

    constructor(uint256 minAmountGas_, address owner_) ONFT721Core(minAmountGas_) {
        super.transferOwnership(owner_); // for create2
    }

    function setNFT(address nft_) external onlyOwner {
        require(nft_ != address(0), "ZeroAddr invalid");
        nft = nft_;
    }

    function _debitFrom(address _from, uint16, bytes memory, uint256 _tokenId) internal virtual override returns (bytes memory) {
        require(nft != address(0), "NFT not set");

        (bool success, bytes memory tier) = nft.call(
            abi.encodeWithSignature("debitFrom(address,address,uint256)", _msgSender(), _from, _tokenId));
        require(success, "NFT call failed");

        return tier;
    }

    function _creditTo(uint16, address toAddress_, uint256 tokenId_, bytes memory tier_) internal virtual override {
        require(nft != address(0), "NFT not set");

        (bool success,) = nft.call(
            abi.encodeWithSignature("creditTo(address,uint256,bytes)", toAddress_, tokenId_, tier_));

        require(success, "NFT call failed");
    }
}

