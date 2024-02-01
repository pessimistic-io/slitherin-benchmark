//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Counters.sol";
import "./Ownable.sol";
import "./ERC721Enumerable.sol";
import "./Strings.sol";
import "./SafeMath.sol";

contract CheatIsland is ERC721Enumerable, Ownable {
    using SafeMath for uint256;
    using Counters for Counters.Counter;
    using Strings for uint256;

    Counters.Counter private _mints;
    string public baseTokenURI;

    address private NFT_Factory = 0xD3E0f2b17Bb9b73637db31bfE535D4F768d2eD73;
    address private Neil_Beloufa = 0xF64C328A7E2628a6685F33AB4F76a7beC1A36340;
    address private Ebb_Global = 0x8308Fc7e81908A088491b87Bb3AcEf82C8182036;
    address private Biche = 0x6b1E47A7BF21424D32151f294bF75965205a3E8F;
    address private Nathan_Notkin = 0xb64F6804Ac8B2c17057892a767C31B701C37DDeb;

    uint256 public mintPrice = 250000000000000000;
    uint256 public maxMints = 12;
    uint256 public openingTime = 1671098400;

    constructor(string memory baseURI) ERC721("Cheat Island", "CI") {
        setBaseURI(baseURI);
    }

    function tokenURI(uint256 tokenId)
        public
        view
        virtual
        override(ERC721)
        returns (string memory)
    {
        _requireMinted(tokenId);
        string memory baseURI = _baseURI();
        return
            bytes(baseURI).length > 0
                ? string(abi.encodePacked(baseURI, tokenId.toString(), ".json"))
                : "";
    }

    function _baseURI() internal view virtual override returns (string memory) {
        return baseTokenURI;
    }

    function setBaseURI(string memory _baseTokenURI) public onlyOwner {
        baseTokenURI = _baseTokenURI;
    }

    // Mint function
    function mintTo(address _adr) internal {
        uint256 newID = _mints.current();
        _safeMint(_adr, newID);
        _mints.increment();
    }

    // Get the current price of the mint
    function getPrice() public view returns (uint256) {
        return mintPrice;
    }

    function getOpeningTime() public view returns (uint256) {
        return openingTime;
    }

    function getCurrent() public view returns (uint256) {
        return _mints.current();
    }

    // Function that a user calls to mint
    function mintArtwork() public payable {
        require(msg.value == mintPrice, "Bad mint price");
        require(block.timestamp > openingTime, "No time to mint");
        require(_mints.current() < maxMints, "Supply filled ");
        mintTo(msg.sender);
    }

    // Set the price of the mint (in wei)
    // Cannot be changed after mint is openned
    function setPrice(uint256 nPrice) public onlyOwner {
        require(block.timestamp < openingTime, "Mint already started");
        mintPrice = nPrice;
    }

    function setOpeningTime(uint256 nOpenning) public onlyOwner {
        require(block.timestamp < openingTime, "Mint already started");
        openingTime = nOpenning;
    }

    // Set max mints allowed
    function setMaxMints(uint256 _maxMints) public onlyOwner {
        require(block.timestamp < openingTime, "Mint already started");
        maxMints = _maxMints;
    }

    function receiveDust() external onlyOwner {
        require(
            address(this).balance < mintPrice,
            "Owner can only receive dust"
        );
        uint256 amount = address(this).balance;
        payable(msg.sender).transfer(amount);
    }

    // Withdraw ETH on the contract
    function claimAndDivide() external onlyOwner {
        uint256 amount = address(this).balance;
        uint256 toNFT_Factory = (amount * 25) / 100;
        uint256 toNeil_Beloufa = (amount * 35) / 100;
        uint256 toBiche = (amount * 10) / 100;
        uint256 toNathan = (amount * 10) / 100;
        uint256 toEbb_Global = (amount * 20) / 100;
        payable(Biche).transfer(toBiche);
        payable(Nathan_Notkin).transfer(toNathan);
        payable(NFT_Factory).transfer(toNFT_Factory);
        payable(Neil_Beloufa).transfer(toNeil_Beloufa);
        payable(Ebb_Global).transfer(toEbb_Global);
    }

    receive() external payable {}

    fallback() external payable {}
}

