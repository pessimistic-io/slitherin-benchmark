// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./ERC1155Upgradeable.sol";
import "./Initializable.sol";
import "./Ownable.sol";
import "./StringsUpgradeable.sol";
import "./SafeMathUpgradeable.sol";

contract FRENSDICE is Initializable, ERC1155Upgradeable {
    string _baseURI = "https://nftstorage.link/ipfs/bafybeiaygz3btjhxy3dpfz5fcakk4vcbxjptvtio7vxcivflosm6datiku/";

    using StringsUpgradeable for string;
    using SafeMathUpgradeable for uint256;

    // address private admin;

    uint256 public counter;

    mapping(uint256 => NFTInfo) public NFTInfoForTokenId;
    mapping(uint256 => string) public _tokenURI;
    mapping(uint256 => mapping(address => uint256)) public buyers;
    mapping(uint256 => mapping(address => uint256)) public payers;

    constructor() {}

    struct NFTInfo {
        uint256 _id;
        uint256 _price;
        uint256 _priceUSD;
        uint256 _num_records;
        uint256 _purchaseValue;
    }

    function initialize() public initializer {
        __ERC1155_init(_baseURI);
    }

    //Only Owner
    function mint(uint256 amount, uint256 price, uint256 priceusd) public {
        counter = counter.add(1);
        NFTInfoForTokenId[counter]._id = counter;
        NFTInfoForTokenId[counter]._price = price;
        NFTInfoForTokenId[counter]._priceUSD = priceusd;
        NFTInfoForTokenId[counter]._num_records = NFTInfoForTokenId[counter]._num_records.add(amount);
        NFTInfoForTokenId[counter]._purchaseValue = 0;
        _tokenURI[counter] = string(abi.encodePacked(_baseURI, StringsUpgradeable.toString(counter), ".json"));
        _mint(msg.sender, counter, amount, "");
    }

    //Only Owner
    function setPurchased(address buyer_addr, uint256 id) public {
        require(payers[id][buyer_addr] > 0, "User didnt bought this track");
        buyers[id][buyer_addr] = NFTInfoForTokenId[id]._purchaseValue;
        NFTInfoForTokenId[id]._num_records = NFTInfoForTokenId[id]._num_records.sub(1);
        NFTInfoForTokenId[id]._purchaseValue = NFTInfoForTokenId[id]._purchaseValue.add(1);
    }

    function purchaseRecord(uint256 id) external payable {
        uint256 amt = msg.value;
        address payable admin = payable(0x018E427F52103851C9C0aAAAd9394a06E1008A70);
        payers[id][msg.sender] = amt;
        admin.transfer(amt);
    }

    function getTrackLink(uint256 _NftId, address buyer_addr) external view returns (string memory) {
        require(buyers[_NftId][buyer_addr] > 0, "User didnt bought this track");
        return _tokenURI[_NftId];
    }

    function uri(uint256 _id) public view virtual override(ERC1155Upgradeable) returns (string memory) {
        return
            bytes(_baseURI).length > 0
                ? string(abi.encodePacked(_baseURI, StringsUpgradeable.toString(_id), ".json"))
                : _baseURI;
    }

    //OnlyOwner
    function setURI(string memory newuri) public {
        _setURI(newuri);
        _baseURI = newuri;
    }
}

