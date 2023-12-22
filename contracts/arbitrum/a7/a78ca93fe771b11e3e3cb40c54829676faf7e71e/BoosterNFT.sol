pragma solidity ^0.8.14;

// SPDX-License-Identifier: MIT

import {ERC721, Address, Strings} from "./ERC721.sol";

import {LootboxTicket} from "./LootboxTicket.sol";

import {IBoosterNFT} from "./IBoosterNFT.sol";
import {IEvoturesNFT} from "./IEvoturesNFT.sol";
import {ILootboxTicket} from "./ILootboxTicket.sol";

contract BoosterNFT is ERC721("Evotures Booster NFTs","EVOBOOST"), IBoosterNFT {
    using Strings for uint8;

    address public immutable dev;
    address public evotures;

    uint16 public constant MAX_SUPPLY = 1800;

    uint16 public lastTokenId;

    mapping(uint16 => BoosterInfo) private _boosterInfo;
    Kind[] private _unminted;

    constructor(Kind[] memory unminted_) {
        dev = msg.sender;

        _safeMint(msg.sender, 1);
        _safeMint(msg.sender, 2);
        lastTokenId = 2;

        for (uint8 i = 0; i < unminted_.length; i++) {
            _unminted.push(unminted_[i]);
        }
    }

    function setEvotures(address _evotures) external {
        require(msg.sender == dev, "BoosterNFT::setEvotures: CALLER_NOT_DEV");
        require(evotures == address(0), "BoosterNFT::setEvotures: EVOTURES_SET");

        evotures = _evotures;
    }

    function mint(uint8 _amount, uint8 _index, uint256[] memory _randomWords, address _to) external returns(uint16[] memory) {
        require(msg.sender == evotures, "BoosterNFT::mint: CALLER_NOT_EVOTURES");
        require((MAX_SUPPLY - lastTokenId) >= _amount, "BoosterNFT::mint: MINT_EXCEEDED");

        uint16[] memory tokenIds = new uint16[](_amount);
        uint8 startIndex = _index + 1;

        for (uint8 i = 0; i < _amount; i++) {
            // Fetch random id
            uint16 rand = uint16(_randomWords[startIndex + i] % _unminted.length);
            uint8 no = _unminted[rand].no;
            lastTokenId++;

            // Mint
            _safeMint(_to, lastTokenId);
            tokenIds[i] = lastTokenId;
            _boosterInfo[lastTokenId].multiplier = _multiplier(no);
            _boosterInfo[lastTokenId].no = no;

            // Reduce no.unminted of minted id, if 0 pop it out from unminted array
            _unminted[rand].unminted--;
            if (_unminted[rand].unminted == 0) {
                _unminted[rand] = _unminted[_unminted.length - 1];
                _unminted.pop();
            }
        }

        return tokenIds;
    }

    function _multiplier(uint8 _no) internal pure returns(uint8 mult) {
        if (_no < 3) {
            mult = 50;
        } else if (_no < 6) {
            mult = 25;
        } else if (_no < 10) {
            mult = 20;
        } else if (_no < 15) {
            mult = 15;
        } else if (_no < 21) {
            mult = 10;
        } else {
            mult = 5;
        }
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        _requireMinted(tokenId);

        string memory baseURI = _baseURI();
        return bytes(baseURI).length > 0 ? string(abi.encodePacked(baseURI, _boosterInfo[uint16(tokenId)].no.toString(), ".json")) : "";
    }

    function _baseURI() internal pure override returns (string memory) {
        return "ipfs://bafybeiboj36pnkuxkla7fmt7xvpx4v5juvgkdqcmdmrnd4nioqkq5fvjca/";
    }

    function contractURI() public pure returns (string memory) {
        return "https://darwinprotocol.io/boosters.json";
    }

    function boosterInfo(uint16 _tokenId) external view returns (BoosterInfo memory) {
        return _boosterInfo[_tokenId];
    }

    function unminted() external view returns (Kind[] memory) {
        return _unminted;
    }
}
