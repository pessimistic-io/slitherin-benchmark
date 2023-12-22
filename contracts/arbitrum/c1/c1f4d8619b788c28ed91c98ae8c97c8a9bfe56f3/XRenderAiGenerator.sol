// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./Counters.sol";
import "./Ownable.sol";
import "./Pausable.sol";
import "./ERC721URIStorage.sol";

contract XRenderAiGenerator is ERC721URIStorage, Ownable, Pausable {
    uint256 private priceMintNFT;
    using Counters for Counters.Counter;
    Counters.Counter private _tokenIds;

    constructor() ERC721("XRender Ai Generator", "XRender") {}

    function mint(string memory tokenURI) external payable returns (uint256) {
        require(!paused(), "Contract is stop");
        require(msg.value == priceMintNFT, "You are engouht balance");

        uint256 _amount = address(this).balance;
        bool sent = payable(owner()).send(_amount);
        require(sent, "Failed to send Ether");

        _tokenIds.increment();
        uint256 newItemId = _tokenIds.current();
        _mint(msg.sender, newItemId);
        _setTokenURI(newItemId, tokenURI);

        return newItemId;
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unPause() external onlyOwner {
        _unpause();
    }

    function setPriceMint(uint256 _priceMintNFT) public onlyOwner {
        priceMintNFT = _priceMintNFT;
    }

    function getPriceMint() public view returns (uint256) {
        return priceMintNFT;
    }
}

