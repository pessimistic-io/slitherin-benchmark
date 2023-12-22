// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./ERC721R.sol";
import "./Ownable.sol";
import "./ReentrancyGuard.sol";

contract AIFundNFTCollection is ERC721r, Ownable, ReentrancyGuard {
    string public tokenURIPrefix;
    uint256 public mintPrice = 0.05 ether; // 0.05 ETH

    bool public isMintingDisabled;

    // 5_000 is the number of tokens in the colletion
    constructor(
        string memory _tokenURIPrefix
    ) ERC721r("AI Fund NFT Collection", "AIFNFT", 5_000) {
        tokenURIPrefix = _tokenURIPrefix;
        isMintingDisabled = false;
    }

    function mint(uint quantity) external payable nonReentrant {
        require(isMintingDisabled == false, "Minting is disabled");
        require(msg.value >= mintPrice * quantity, "Insufficient funds");

        _mintRandom(msg.sender, quantity);
    }

    function setMintPrice(uint256 _mintPrice) external onlyOwner {
        mintPrice = _mintPrice;
    }

    function setMintingDisabled(bool _value) external onlyOwner {
        isMintingDisabled = _value;
    }

    /// @notice Withdraw ETH to owner
    function withdrawFunds() external onlyOwner {
        payable(owner()).transfer(address(this).balance);
    }

    /**
     * @dev See {IERC721Metadata-tokenURI}.
     */
    function tokenURI(
        uint256 tokenId
    ) public view virtual override returns (string memory) {
        require(
            _exists(tokenId),
            "ERC721Metadata: URI query for nonexistent token"
        );

        string memory baseURI = _baseURI();
        return
            bytes(baseURI).length > 0
                ? string(
                    abi.encodePacked(
                        baseURI,
                        tokenId < 499 ? "gold" : "silver"
                    )
                )
                : "";
    }

    /**
     * @dev Base URI for computing {tokenURI}. If set, the resulting URI for each
     * token will be the concatenation of the `baseURI` and the `tokenId`. Empty
     * by default, can be overridden in child contracts.
     */
    function _baseURI() internal view virtual override returns (string memory) {
        return tokenURIPrefix;
    }
}

