// SPDX-License-Identifier: MIT
//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&
//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&
//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&
//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&
//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&
//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&
//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&
//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&
//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&
//&&&&&&&&&,*,,,,,,/%&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&%*,,&&&&&&&&
//&&&&&&&&&,*%%%%%%%,,,,*,,%&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&**,,,,,,*&&&&&&&&&
//&&&&&&&&&&,%%%%%%%%%%%,,,,,,,,(&&&&&&&&&&&&&&&&&&&&&&&&&&(,,,,,,,,%%,#&&&&&&&&&&
//&&&&&&&&&&,,%%%%%%%%%%%%%&,,,,,,,,*&&&&&&&%&&,%&&&&&&*,,,,,,,,,*%%#,%&&&&&&&&&&&
//&&&&&&&&&&&,,%%%%%%%%%%%%%%%%,,,,,,,,,&&,,,,#,,,&/,,,,,,,,,,,,%%%&,#&&&&&&&&&&&&
//&&&&&&&&&&&&,*%%%%%%%%%%%%%%%%%,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,%%%%,/&&&&&&&&&&&&&
//&&&&&&&&&&&&&,,/%%%%%%%%%%%%%%#(,,,,,,,,,,,,,,,,,,,,,,,,,,,,%%%%,%&&&&&&&&&&&&&&
//&&&&&&&&&&&&&&&*,,%%%%%%%%%%%&%,,,,,,,,,,,,,,,,,,,,,,,,,,,(%%&/*&&&&&&&&&&&&&&&&
//&&&&&&&&&&&&&&&&&/,,,#%%%%%%%*(,,,,,,,,,/%%%,,,,,,,,,,,,,((&*,%&&&&&&&&&&&&&&&&&
//&&&&&&&&&&&&&&&&&&&&&/,,,,,,,,,,,,,,,,*%%&(&&%,,,,*(,,,,,,,,%&&&&&&&&&&&&&&&&&&&
//&&&&&&&&&&&&&&&&&&&&&&#,,,,,,,,,,,,,,,,%%    (,,,#  ,,,,,,*&&&&&&&&&&&&&&&&&&&&&
//&&&&&&&&&&&&&&&&&&&&&,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,#&&&&&&&&&&&&&&&&&&&
//&&&&&&&&&&&&&&&&&&&&&&(,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,&&&&&&&&&&&&&&&&&&
//&&&&&&&&&&&&&&&&&&&&&&&&&&#,,,,,,,,,,,,,,,,,,,,,**,,,,,,,,,,,*&&&&&&&&&&&&&&&&&&
//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&(,,,,,,,,,,,,,,,,,,,(&&&&&&&&&&&&&&&&&&&&&&
//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&
//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&
//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&
//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&
//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&
//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&
//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&
//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&
pragma solidity ^0.8.12;

import "./ERC721Enumerable.sol";
import "./MerkleProof.sol";
import "./Ownable.sol";
import "./Strings.sol";

struct Infos {
    bool revealed;
    uint16 wlMaxSupply;
    uint32 wlDate;
    uint32 raffleDate;
    uint128 regularPrice;
    uint128 wlPrice;
}

contract Lendarys is Ownable, ERC721Enumerable {
    using Strings for uint256;
    bytes32 merkleRoot;
    uint16 public constant MAX_SUPPLY = 6000;
    string private baseURI;
    string private revealURI;
    Infos public v =
        Infos(false, 500, 2**32 - 1, 2**32 - 1, 0.06 ether, 0.08 ether);

    mapping(address => uint256) public wlMinted;

    address payable public immutable teamAddress;

    constructor(string memory _URI, address payable _teamAddress)
        ERC721("Lendarys", "LEND")
    {
        revealURI = _URI;
        teamAddress = _teamAddress;
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId
    ) internal virtual override {
        super._beforeTokenTransfer(from, to, tokenId);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    function whitelistMint(uint256 amount, bytes32[] calldata _proof)
        external
        payable
    {
        uint256 ts = totalSupply();
        Infos memory vBuffer = v;
        require(_verify(_proof), "Not whitelisted");
        uint256 wlMinted_ = wlMinted[msg.sender];
        require(
            uint64(block.timestamp) >= vBuffer.wlDate,
            "Whitelist sale is not activated"
        );
        require(msg.value >= vBuffer.regularPrice * amount, "Not enough funds");
        require(ts + amount <= MAX_SUPPLY, "Exceed available supply");
        require(wlMinted_ + amount <= 3, "Minted too much for whitelist sale");
        wlMinted[msg.sender] = wlMinted_ + amount;
        mint(msg.sender, amount, ts);
    }

    function publicSaleMint(uint256 amount) external payable {
        uint256 ts = totalSupply();
        Infos memory vBuffer = v;
        require(
            uint64(block.timestamp) >= vBuffer.raffleDate,
            "Public sale is not activated"
        );
        require(ts + amount <= MAX_SUPPLY, "Exceed available supply");
        require(msg.value >= vBuffer.regularPrice * amount, "Not enough funds");
        mint(msg.sender, amount, ts);
    }

    function give(address[] calldata addresses, uint256[] calldata amounts)
        external
        onlyOwner
    {
        uint256 total = 0;
        for (uint256 i = 0; i < addresses.length; ) {
            total += amounts[i];
            ++i;
        }
        require(total + totalSupply() <= MAX_SUPPLY, "Too much to give");
        require(
            addresses.length == amounts.length,
            "Differences between nb of amounts and addresses"
        );
        unchecked {
            for (uint256 i = 0; i < addresses.length; ) {
                mint(addresses[i], amounts[i], totalSupply());
                ++i;
            }
        }
    }

    function mint(
        address to,
        uint256 amount,
        uint256 ts
    ) internal {
        unchecked {
            for (uint256 i = 0; i < amount; ) {
                ++i;
                _safeMint(to, ts + i);
            }
        }
    }

    /*Setters
     */

    function setWlDate(uint32 wlDate) external onlyOwner {
        v.wlDate = wlDate;
    }

    function setRaffleDate(uint32 date) external onlyOwner {
        v.raffleDate = date;
    }

    function setPrices(uint128 wlPrice, uint128 price) external onlyOwner {
        if (wlPrice > 0) {
            v.wlPrice = wlPrice;
        }
        if (price > 0) {
            v.regularPrice = price;
        }
    }

    function switchReveal() external onlyOwner {
        v.revealed = !v.revealed;
    }

    function setRevealURI(string memory _URI) external onlyOwner {
        revealURI = _URI;
    }

    function setBaseUri(string memory _URI) external onlyOwner {
        baseURI = _URI;
    }

    function setMerkleRoot(bytes32 _merkleRoot) external onlyOwner {
        merkleRoot = _merkleRoot;
    }

    function tokenURI(uint256 _tokenId)
        public
        view
        virtual
        override
        returns (string memory)
    {
        require(_exists(_tokenId), "URI query for nonexistent token");
        if (v.revealed) {
            return
                string(abi.encodePacked(baseURI, _tokenId.toString(), ".json"));
        }
        return
            string(abi.encodePacked(revealURI, _tokenId.toString(), ".json"));
    }

    function _verify(bytes32[] calldata _proof) internal view returns (bool) {
        return
            MerkleProof.verify(
                _proof,
                merkleRoot,
                keccak256(abi.encodePacked(msg.sender))
            );
    }

    function withdraw() external {
        uint256 balance = address(this).balance;
        (bool success, ) = teamAddress.call{value: balance}("");
        require(success, "withdraw error");
    }
}

