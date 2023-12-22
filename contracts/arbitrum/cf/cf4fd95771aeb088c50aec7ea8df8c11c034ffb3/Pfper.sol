//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "./console.sol";
import "./Base64.sol";
import "./Strings.sol";
import "./Counters.sol";
import "./ERC721Enumerable.sol";
import "./Ownable.sol";

contract Pfper is ERC721Enumerable, Ownable {
    using Counters for Counters.Counter;

    uint256 private _cost;
    uint256 private _sellerFeeBasisPoints;
    Counters.Counter private _tokenCounter;

    mapping(uint256 => string) private _tokenCIDs;
    mapping(string => uint256) private _minted;
    mapping(uint256 => address) private _authors;

    constructor(uint256 cost, uint256 sellerFeeBasisPoints) ERC721("pfper", "PFPER") Ownable() {
        _cost = cost;
        _sellerFeeBasisPoints = sellerFeeBasisPoints;
    }

    function getCost() public view returns (uint256) {
        return _cost;
    }

    function setCost(uint256 cost) public onlyOwner {
        _cost = cost;
    }

    function getSellerFeeBasisPoints() public view returns (uint256) {
        return _sellerFeeBasisPoints;
    }

    function setSellerFeeBasisPoints(uint256 sellerFeeBasisPoints) public onlyOwner {
        _sellerFeeBasisPoints = sellerFeeBasisPoints;
    }

    function mintPfp(string memory cid) public payable {
        require(msg.value >= _cost, 'mint payment insufficient');
        require(_minted[cid] == 0, 'pfp already minted');
        _tokenCounter.increment();
        uint256 tokenId = _tokenCounter.current();
        _tokenCIDs[tokenId] = cid;
        _minted[cid] = tokenId;
        _authors[tokenId] = msg.sender;
        _safeMint(msg.sender, tokenId);
    }

    function authorOf(uint256 tokenId) public view returns (address) {
        return _authors[tokenId];
    }

    function tokenURI(uint256 tokenId) override public view returns (string memory) {
        string memory cid = _tokenCIDs[tokenId];
        string memory json = string(abi.encodePacked(
            '{"name":"pfper #', Strings.toString(tokenId), '",',
            '"description":"each pfper is drawn by its author.",',
            '"image":"ipfs://', cid, '",',
            '"seller_fee_basis_points":', Strings.toString(_sellerFeeBasisPoints), ',',
            '"fee_recipient":"',Strings.toHexString(uint256(uint160(address(this))), 20),'"}'
        ));
        string memory b64json = Base64.encode(bytes(json));
        string memory output = string(abi.encodePacked('data:application/json;base64,', b64json));
        return output;
    }

    function withdraw() public onlyOwner {
        payable(msg.sender).transfer(address(this).balance);
    }
}

