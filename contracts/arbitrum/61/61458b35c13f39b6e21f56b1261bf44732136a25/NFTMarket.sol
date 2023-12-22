// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Imsw.sol";
import "./IERC20.sol";
import "./AddressUpgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./Initializable.sol";

contract NFTMarket is OwnableUpgradeable {
    using AddressUpgradeable for address;
    address public WALLET;
    address public USDT;
    address public unionsAddress;
    IMSW721 public unions;
    mapping(address => uint[]) public userBuyNFTs;

    // event
    event BuyNFT(
        address indexed user,
        uint indexed cardId,
        uint indexed tokenId
    );

    // init
    function init() public initializer {
        __Context_init_unchained();
        __Ownable_init_unchained();
        WALLET = 0x42eCa52e786Dcd81757E0C2baF99A92eFE7FF559;
        USDT = 0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9;

        setMsw721(0xa3F9Ed664C5216505b759ac0AD6b99604090a89a);
    }

    // dev
    function setWallet(address wallet_) public onlyOwner {
        WALLET = wallet_;
    }

    function setMsw721(address msw721_) public onlyOwner {
        unionsAddress = msw721_;
        unions = IMSW721(msw721_);
    }

    function setUSDT(address usdt_) public onlyOwner {
        USDT = usdt_;
    }

    // view
    function nftPrice(uint cardId_) public view returns (uint) {
        (, , , uint price, ) = unions.cardInfoes(cardId_);
        return price;
    }

    // user
    function buyNFTWithUSDT(uint cardId_) public {
        require(
            IERC20(USDT).transferFrom(
                msg.sender,
                address(this),
                nftPrice(cardId_)
            ),
            "transferFrom error!"
        );
        unions.mint(msg.sender, cardId_, 1);
        uint tokenId = unions.cardIdMap(cardId_);
        userBuyNFTs[msg.sender].push(tokenId);
        emit BuyNFT(msg.sender, cardId_, tokenId);
    }
}

