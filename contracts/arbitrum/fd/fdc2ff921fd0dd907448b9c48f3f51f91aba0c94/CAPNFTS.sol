// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import "./ERC721B.sol";
import "./Ownable.sol";
import "./Strings.sol";
import "./IERC20.sol";

error OverMaxSupply();
error WrongEtherValue();
error transferFromFailed();
error OverMintLimit();
error SaleNotActive();

contract CAPNFTS is ERC721B, Ownable {
    using Strings for uint256;

    IERC20 public CAP = IERC20(0x031d35296154279DC1984dCD93E392b1f946737b); // CAP Token contract on Arbitrum

    // collection specific parameters
    string private baseURI;
    bool public publicSaleActive;

    uint256 constant supply = 540;
    uint256 constant price = 0.02 ether;
    uint256 constant maxBatchSize = 20;

    constructor() ERC721B('CAPMEMORIALNFT', 'CAPNFT') {}

    /*///////////////////////////////////////////////////////////////
                          OWNER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function withdraw() external onlyOwner {
        uint256 balance = address(this).balance;
        payable(msg.sender).transfer(balance);
    }

    function withdrawCAP() external onlyOwner {
        uint256 balance = CAP.balanceOf(address(this));
        CAP.transfer(msg.sender, balance);
    }

    function withdrawERC20(IERC20 _ERC20) external onlyOwner {
        uint256 balance = _ERC20.balanceOf(address(this));
        _ERC20.transfer(msg.sender, balance);
    }

    function setBaseURI(string calldata _baseURI) external onlyOwner {
        baseURI = _baseURI;
    }

    function togglePublicSale() external onlyOwner {
        publicSaleActive = !publicSaleActive;
    }

    /**
     * Reserve NFTs for giveaways
     */
    function adminReserve(uint256 qty) external onlyOwner {
        if ((_owners.length + qty) > supply) revert OverMaxSupply();

        _mint(msg.sender, qty);
    }

    function mint(uint256 qty, bool payViaCAP) external payable {
        if (!publicSaleActive) revert SaleNotActive();
        if (qty > maxBatchSize) revert OverMintLimit();
        if ((_owners.length + qty) > supply) revert OverMaxSupply();

        if (payViaCAP) {
            if (!CAP.transferFrom(msg.sender, address(this), qty * 10**18)) revert transferFromFailed();
        } else {
            if (msg.value < price * qty) revert WrongEtherValue();
        }

        _safeMint(msg.sender, qty);
    }

    /**
     * @dev See {IERC721Metadata-tokenURI}.
     */
    function tokenURI(uint256 _tokenId) public view override returns (string memory) {
        if (!_exists(_tokenId)) revert URIQueryForNonexistentToken();
        return string(abi.encodePacked(baseURI, Strings.toString(_tokenId)));
    }
}

