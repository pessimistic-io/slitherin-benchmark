//Contract based on [https://docs.openzeppelin.com/contracts/3.x/erc721](https://docs.openzeppelin.com/contracts/3.x/erc721)
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Ownable.sol";
import "./console.sol";

contract DeployedPunknpunks {
    function mintedTokenIds() public view returns (uint256[] memory) {}
    function mintNFT(address recipient, uint256 pnpId) public payable returns (uint256) {}
}


contract Multiminter is Ownable {
    uint256 public constant MAX_SUPPLY = 10000;
    uint256 public constant NFT_PRICE = 10000000000000000; // 0.01 ETH
    // Needed functions from minting contract.
    DeployedPunknpunks pnp;

    constructor(address _address) {
        // _address of the punknpunk contract on arbitrum.
        pnp = DeployedPunknpunks(_address);
    }

    function setWrapContract(address _address) public onlyOwner {
        pnp = DeployedPunknpunks(_address);
    }

    //TODO!!! Not needed.
    function getMinted() public view returns (uint256[] memory) {
        return(pnp.mintedTokenIds());
    }

    // Mints by token ID.
    function multiMintNFT(address recipient, uint256[] memory pnpIds) public payable returns(uint256[] memory) {
        require(msg.value == pnpIds.length * NFT_PRICE, "Correct eth amount must be sent for punks minted.");
        for (uint i=0; i < pnpIds.length; i++) {
            pnp.mintNFT{value:NFT_PRICE}(recipient, pnpIds[i]);
        }
        // uint256 test = pnp.mintNFT{value:msg.value }(recipient, pnpId);
        return pnpIds;
    }

}
