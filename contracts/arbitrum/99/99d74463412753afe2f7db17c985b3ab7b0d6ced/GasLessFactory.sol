// Contract based on https://docs.openzeppelin.com/contracts/4.x/erc721
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;
import {GasLessNFT} from "./GasLessNFT.sol";

contract GasLessFactory {
    GasLessNFT private nftAddress;

    function createInstance(
        string memory _name,
        string memory _symbol,
        address recipient,
        string memory tokenURI,
        uint256 numNfts
    ) public {
        require(msg.sender != address(0), "Address should not be empty");
        nftAddress = new GasLessNFT(_name, _symbol);
        _createNfts(recipient, tokenURI, numNfts);
    }

    function _createNfts(
        address recipient,
        string memory tokenURI,
        uint256 numNfts
    ) private {
        nftAddress.mintNFT(recipient, tokenURI, numNfts);
    }
}

