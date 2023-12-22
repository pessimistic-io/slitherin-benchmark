pragma solidity ^0.8.14;

// SPDX-License-Identifier: MIT

import {ERC721, IERC721, Address, Strings} from "./ERC721.sol";
import {IERC721Receiver} from "./IERC721Receiver.sol";

import {IEvoturesNFT} from "./IEvoturesNFT.sol";
import {IBoosterNFT} from "./IBoosterNFT.sol";

interface IVRFv2Consumer {
    function requestRandomWords(uint8 evotures, uint8 boosters, address minter) external returns (uint256 requestId);
}

contract EvoturesNFT is ERC721("Evotures NFTs","EVOTURES"), IEvoturesNFT, IERC721Receiver {
    using Strings for uint256;

    address public immutable dev;
    IBoosterNFT public immutable boosterContract;
    IVRFv2Consumer public immutable vrfConsumer;

    uint16 public totalMinted;
    uint64 public constant EVOTURES_PRICE = 0.04 ether;
    uint64 public constant BOOSTER_PRICE = 0.006 ether;

    uint16[] private _unminted;
    mapping(address => uint16[]) private _userMinted;
    mapping(uint16 => uint16[]) private _boostersApplied;

    constructor(uint16[] memory unminted_, IBoosterNFT _boosterContract, IVRFv2Consumer _vrfConsumer) {
        // Set Dev, unminted, booster and vrf consumer contracts
        dev = msg.sender;
        _unminted = unminted_;
        boosterContract = _boosterContract;
        vrfConsumer = _vrfConsumer;

        // Mint mythical evotures
        _safeMint(msg.sender, 2061);
        _safeMint(msg.sender, 2120);
        totalMinted = 2;
    }

    // This will be called by the deployer address (thru backend) when the NFT mint is done on the Ethereum Mainnet chain
    function hardMint(uint8 _evotures, uint8 _boosters, address to) external {
        require(msg.sender == dev, "EvoturesNFT::hardMint: CALLER_NOT_DEV");
        require(_unminted.length >= _evotures, "EvoturesNFT::hardMint: MINT_EXCEEDED");
        require(_evotures <= (3 - _userMinted[to].length) && _boosters <= 5, "EvoturesNFT::hardMint: FORBIDDEN");

        vrfConsumer.requestRandomWords(_evotures, _boosters, to);
    }

    function mint(uint8 _evotures, uint8 _boosters, address to) external payable {
        require(_unminted.length >= _evotures, "EvoturesNFT::mint: MINT_EXCEEDED");
        require(_evotures <= (3 - _userMinted[to].length) && _boosters <= 5, "EvoturesNFT::mint: FORBIDDEN");
        require(msg.value >= (_evotures*EVOTURES_PRICE + _evotures*_boosters*BOOSTER_PRICE), "EvoturesNFT::mint: INSUFFICIENT_ETH");

        vrfConsumer.requestRandomWords(_evotures, _boosters, to);
    }

    function chainlinkMint(uint256[] memory _randomWords, uint8 _evotures, uint8 _boosters, address _minter) external {
        require(msg.sender == address(vrfConsumer), "EvoturesNFT::chainlinkMint: CALLER_NOT_CONSUMER");

        for (uint8 i = 0; i < _evotures; i++) {
            // Mint
            uint16 id = uint16(_randomWords[i * _boosters + i] % _unminted.length);
            _safeMint(_minter, _unminted[id]);
            totalMinted++;
            _userMinted[_minter].push(_unminted[id]);

            // Mint boosters and map them to the minted evoture tokenId
            _boostersApplied[_unminted[id]] = boosterContract.mint(_boosters, i, _randomWords, address(this));

            // Pop out minted id from unminted array
            _unminted[id] = _unminted[_unminted.length - 1];
            _unminted.pop();
        }
    }

    function burn(uint256 tokenId) external {
        address owner = ownerOf(tokenId);
        require(msg.sender == owner, "EvoturesNFT::burn: CALLER_NOT_OWNER");
        _burn(tokenId);
    }

    function addBooster(uint16 _tokenId, uint16 _boosterTokenId) external {
        require(ownerOf(_tokenId) == msg.sender, "EvoturesNFT::addBooster: CALLER_NOT_EVOTURE_OWNER");
        require(_boostersApplied[_tokenId].length < 5, "EvoturesNFT::addBooster: MAX_BOOSTERS_ADDED");
        IERC721(address(boosterContract)).safeTransferFrom(msg.sender, address(this), _boosterTokenId);
        _boostersApplied[_tokenId].push(_boosterTokenId);
    }

    function removeBooster(uint16 _tokenId, uint16 _boosterTokenId) external {
        require(ownerOf(_tokenId) == msg.sender, "EvoturesNFT::removeBooster: CALLER_NOT_EVOTURE_OWNER");
        require(_boostersApplied[_tokenId].length > 0, "EvoturesNFT::removeBooster: NO_BOOSTER_ADDED");
        IERC721(address(boosterContract)).safeTransferFrom(address(this), msg.sender, _boosterTokenId);
        for (uint8 i = 0; i < _boostersApplied[_tokenId].length; i++) {
            if (_boostersApplied[_tokenId][i] == _boosterTokenId) {
                _boostersApplied[_tokenId][i] = _boostersApplied[_tokenId][_boostersApplied[_tokenId].length - 1];
                _boostersApplied[_tokenId].pop();
                break;
            }
        }
    }

    function withdrawETH() external {
        // Withdraw raised eth
        require (msg.sender == dev, "EvoturesNFT::withdrawETH: CALLER_NOT_DEV");
        (bool success, ) = payable(msg.sender).call{value: address(this).balance}("");
        require(success, "EvoturesNFT::withdrawETH: TRANSFER_FAILED");
    }

    function multipliers(uint16 id) external view returns(uint16 mult) {
        uint16[] memory boostersIds = _boostersApplied[id];
        for (uint8 i = 0; i < boostersIds.length; i++) {
            mult += boosterContract.boosterInfo(boostersIds[i]).multiplier;
        }
        if (id == 2061 || id == 2120) {
            mult += 1000;
        } else {
            if (id > 2000) {
                id-=2000;
            } else if (id > 1000) {
                id-=1000;
            }
            if (id < 3) {
                mult += 500;
            } else if (id < 8) {
                mult += 400;
            } else if (id < 20) {
                mult += 300;
            } else if (id < 40) {
                mult += 250;
            } else {
                mult += 200;
            }
        }
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        _requireMinted(tokenId);

        string memory baseURI = _baseURI();
        return bytes(baseURI).length > 0 ? string(abi.encodePacked(baseURI, tokenId.toString(), ".json")) : "";
    }

    function _baseURI() internal pure override returns (string memory) {
        return "ipfs://bafybeicrhiw7aaa32azbtmhlppz7xzopmyvhvidwz3ys27a6u4s6ai6gai/";
    }

    function contractURI() public pure returns (string memory) {
        return "https://darwinprotocol.io/evotures.json";
    }

    function unminted() external view returns (uint16[] memory) {
        return _unminted;
    }

    function userMinted(address _user) external view returns (uint16[] memory) {
        return _userMinted[_user];
    }

    function boosters(uint16 _tokenId) external view returns (uint16[] memory) {
        return _boostersApplied[_tokenId];
    }

    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) external pure returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }

    receive() external payable {}
}
