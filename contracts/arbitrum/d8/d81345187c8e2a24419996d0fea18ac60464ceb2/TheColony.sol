// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

/// Contract @title: The Colony
/// Contract @author: Stinky (@nomamesgwei)
/// Description @dev: Artist OᗷᒪOᗰOᐯ project
/// Version @notice: 0.2

import "./ERC721A.sol";
import "./Ownable.sol";

contract TheColony is ERC721A, Ownable {

    /// @dev baseURI for NFT Metadata
    string public baseURI;
    /// @dev Beneficiary Address
    address public beneficiary;
    /// @dev Max Supply
    uint256 immutable public maxSupply = 999;
    /// @dev Mint Shutoff
    bool public mintOpen;
    /// @dev Price to Mint an NFT
    uint256 public mintPrice = 0.01 ether;

    /// @dev Throw when minting during Mint Close
    error MintClosed();
    /// @dev Throw if NFT is Minted Out
    error MintedOut();
    /// @dev Throw if not in public mint phase
    error NotPublicMint();
    /// @dev Throw if Address list doesn't match Prize list
    error InvalidAirdrop();
    /// @dev Throw if someone is tyring to mint 0 quanity
    error ZeroMint();

    constructor(string memory uri, address benef) ERC721A('The Colony', 'COLON') {
        beneficiary = benef;
        baseURI = uri;
        mintOpen = true;
    }

    /// @dev This Project starts at ID 1
    function _startTokenId() internal pure override returns (uint256) {
        return 1;
    }

    /// @dev Public Mint NFTs
    /// @param quantity Number of NFTs to mint
    function mint(uint256 quantity) external payable {
        if(!mintOpen) { revert MintClosed(); }
        if(quantity < 1) { revert ZeroMint(); }
        if(_totalMinted() + quantity > maxSupply) { revert MintedOut(); }
        require(msg.value == mintPrice * quantity, "ETH value incorrect");
        // if((mintPrice * quantity) != msg.value) { revert InsufficientFunds(); }
        _mint(_msgSender(), quantity);
    }

    /// @dev Oblomov is Crypto Oprah
    /// @param winners The list of address receive airdrop
    function airdrop(address[] calldata winners, uint256[] calldata prizes) external onlyOwner {
        uint256 win_length = winners.length;
        if(win_length != prizes.length) { revert InvalidAirdrop(); }
        if(_totalMinted() + win_length > maxSupply) { revert MintedOut(); }
        for (uint i; i < win_length;) {
            _mint(winners[i], prizes[i]);
            // Cannot possibly overflow due to size of array
            unchecked {++i;}            
        }
    }

    /// @dev Returns TokenURI for Marketplaces
    /// @param tokenId The ID of the Token you want Metadata for
    function tokenURI(uint256 tokenId) override public view returns (string memory) {
        return string(abi.encodePacked(baseURI, _toString(tokenId), ".json"));
    }

    /// @dev Change beneficiary address
    function updateBeneficiary(address newBenef) public onlyOwner {
        beneficiary = newBenef;
    }

    /// @dev Mint Open Toggle
    function updateMintStatus() public onlyOwner {
        mintOpen = !mintOpen;
    }

    /// @dev Change the price of mint (create promos)
    function updatePrice(uint256 newPrice) external onlyOwner {
        mintPrice = newPrice;
    }

    /// @dev Withdraw funds from Contract
    function withdraw() external onlyOwner {
        payable(beneficiary).transfer(address(this).balance);
    }
}
