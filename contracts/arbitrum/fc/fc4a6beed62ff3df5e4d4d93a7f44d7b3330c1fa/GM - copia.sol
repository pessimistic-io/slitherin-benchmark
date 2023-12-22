// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import "./ReentrancyGuard.sol";
import "./Ownable.sol";

interface IFREN {
    function balanceOf(address) external view returns (uint256);

    function transfer(address to, uint256 amount) external returns (bool);

    function allowance(address owner, address spender) external view returns (uint256);

    function approve(address spender, uint256 amount) external returns (bool);

    function transferFrom(address from, address to, uint256 amount) external returns (bool);

    function ownerOf(uint256 tokenId) external view returns (address);
}

contract FrenHat is Ownable, ReentrancyGuard {
    address public Phat_NFT = 0xb75DB4EF3615E954b29c690B76Af994Ad41d04D5;
    address public Phat1_NFT = 0xAf4a2633621B9B0bc49B2D29A0CeAc2Ca680D352;
    address public Fren_NFT = 0x249bB0B4024221f09d70622444e67114259Eb7e8;
    address public Phat_Token = 0x69b2cd28B205B47C8ba427e111dD486f9C461B57;
    address public Fren_Token = 0x54cfe852BEc4FA9E431Ec4aE762C33a6dCfcd179;
    address public Trimmed_Phat_Token = 0x35d1d6f8EBC86B8DF9266f3Bb574F666A9543473;
    address public constant fren_grave = 0x000000000000000000000000000000000000dEaD;
    uint256 public HatPrice = 42069 * 1e18;
    mapping(uint256 => bool) public _hasHat;
    mapping(address => bool) private _isNonFren;

    constructor() {}

    function setAddress(
        address _Phat_NFT,
        address _Phat1_NFT,
        address _Fren_NFT,
        address _Phat_Token,
        address _Fren_Token
    ) public onlyOwner {
        Phat_NFT = _Phat_NFT;
        Phat1_NFT = _Phat1_NFT;
        Fren_NFT = _Fren_NFT;
        Phat_Token = _Phat_Token;
        Fren_Token = _Fren_Token;
    }

    function setHatPrice(uint256 _HatPrice) public onlyOwner {
        HatPrice = _HatPrice;
    }

    function getHat(uint256 _tokenID) public {
        require(!_isNonFren[msg.sender], "No Non Frens Allowed");
        require(msg.sender == IFREN(Fren_NFT).ownerOf(_tokenID), "You must own this Fren to put an Hat on");
        require(IFREN(Fren_Token).balanceOf(tx.origin) > HatPrice, "You must have $NFA to burn for Hat");
        require(
            IFREN(Phat_Token).balanceOf(tx.origin) > 0 ||
                IFREN(Phat_NFT).balanceOf(tx.origin) > 0 ||
                IFREN(Phat1_NFT).balanceOf(tx.origin) > 0 ||
                IFREN(Trimmed_Phat_Token).balanceOf(tx.origin) > 0,
            "You must have an Hat to put on your Fren"
        );
        IFREN(Fren_Token).transferFrom(msg.sender, fren_grave, HatPrice);
        _hasHat[_tokenID] = true;
    }

    function hasHat(uint256 _tokenID) public returns (bool) {
        return _hasHat[_tokenID];
    }

    function setNonFrens(address[] calldata _addresses, bool bot) public onlyOwner {
        for (uint256 i = 0; i < _addresses.length; i++) {
            _isNonFren[_addresses[i]] = bot;
        }
    }
}

