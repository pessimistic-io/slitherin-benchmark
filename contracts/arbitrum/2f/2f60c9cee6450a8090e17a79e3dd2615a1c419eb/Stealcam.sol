// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import "./ERC721.sol";
import "./ECDSA.sol";
import "./Strings.sol";
import "./Ownable.sol";
import "./console.sol";

contract Stealcam is ERC721, Ownable {
    
    using ECDSA for bytes32;
    using Strings for uint256;

    event Stolen(address from, address to, uint256 id, uint256 value);

    string public baseUri;
    mapping(uint256 => uint256) public previousStealPrice;
    mapping(uint256 => address) public creator;

    constructor(
        string memory _name,
        string memory _symbol
    ) ERC721(_name, _symbol) {}

    function tokenURI(uint256 id) public view virtual override returns (string memory) {
        return string(abi.encodePacked(baseUri, id.toString()));
    }

    function setBaseUri(string calldata _baseUri) public onlyOwner {
        baseUri = _baseUri;
    }

    function mint(uint256 id, address _creator, bytes calldata signature) public {
        bytes32 hash = keccak256(abi.encodePacked(id, _creator));
        bytes32 messageHash = hash.toEthSignedMessageHash();
        address signer = messageHash.recover(signature);
        require(signer == owner(), "Not signed by owner");

        _mint(msg.sender, id);
        creator[id] = _creator;
        emit Stolen(_creator, msg.sender, id, 0);
    }

    function mint(uint256 id, address _creator) public onlyOwner {
        _mint(msg.sender, id);
        creator[id] = _creator;
        emit Stolen(_creator, msg.sender, id, 0);
    }

    function steal(uint256 id) public payable {
        require(_ownerOf[id] != address(0), 'Does not exist');
        require(msg.value >= previousStealPrice[id] * 110 / 100 + 0.001 ether, 'Insufficient payment');

        address previousOwner = ownerOf(id);
        uint256 surplus = msg.value - previousStealPrice[id];
        uint256 creatorPayment = surplus * 45 / 100;
        uint256 previousOwnerPayment = previousStealPrice[id] + creatorPayment;

        _ownerOf[id] = msg.sender;
        previousStealPrice[id] = msg.value;

        emit Transfer(previousOwner, msg.sender, id);
        emit Stolen(previousOwner, msg.sender, id, msg.value);

        payable(previousOwner).transfer(previousOwnerPayment);
        payable(creator[id]).transfer(creatorPayment);
    }

    function withdraw() public onlyOwner {
        payable(msg.sender).transfer(address(this).balance);
    }
}
