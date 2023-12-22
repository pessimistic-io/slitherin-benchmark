// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./console.sol";
import "./IERC20.sol";
import "./Strings.sol";
import "./ERC721Enumerable.sol";
import "./Ownable.sol";
import "./Counters.sol";

contract Unions is Ownable, ERC721Enumerable {
    using Address for address;
    using Strings for uint256;
    using Counters for Counters.Counter;
    Counters.Counter private _tokenIds;

    string public myBaseURI;

    address public superMinter;
    address public WALLET;
    address public USDT;

    struct CardInfo {
        uint cardId;
        uint currentAmount;
        uint level;
        uint price;
        string tokenURI;
    }

    // minter
    mapping(address => bool) public superMinters;
    mapping(address => mapping(uint => uint)) public minters;

    // card info
    mapping(uint => uint) public cardIdMap;
    mapping(uint => CardInfo) public cardInfoes;
    // mapping(uint => address) private cardOwners;

    // event
    event NewCard(uint indexed cardId);
    event Mint(address indexed user, uint indexed cardId, uint indexed tokenId);
    event Upgrade(
        address indexed user,
        uint indexed tokenId,
        uint indexed toCardId
    );
    // modifier
    modifier onlySuperMinters() {
        require(superMinters[msg.sender], "not superMinters!");
        _;
    }

    // constructor
    constructor() ERC721("MSW-Unions", "Unions") {
        superMinter = msg.sender;
        superMinters[msg.sender] = true;
        WALLET = 0x42eCa52e786Dcd81757E0C2baF99A92eFE7FF559;
        USDT = 0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9;
        myBaseURI = "https://ipfs.io/ipfs/QmcF9rVTUQa3jwGbr3iy3dYkfnMfhAAbP72iDMCW6JcQ4V";
    }

    function supportsInterface(
        bytes4 interfaceId
    ) public view override(ERC721Enumerable) returns (bool) {
        return
            interfaceId == type(IERC721).interfaceId ||
            interfaceId == type(IERC721Enumerable).interfaceId ||
            interfaceId == type(IERC721Metadata).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    // dev
    function setSuperMinter(
        address newSuperMinter_,
        bool b
    ) public onlyOwner returns (bool) {
        superMinters[newSuperMinter_] = b;
        return true;
    }

    function setMinter(
        address newMinter_,
        uint[] calldata cardId_,
        uint[] calldata amount_
    ) public onlyOwner returns (bool) {
        for (uint i; i < cardId_.length; i++) {
            minters[newMinter_][cardId_[i]] = amount_[i];
        }
        return true;
    }

    function setWALLET(address addr_) public onlyOwner {
        WALLET = addr_;
    }

    function setU(address u_) public onlyOwner {
        USDT = u_;
    }

    function setMyBaseURI(string calldata uri_) public onlyOwner {
        myBaseURI = uri_;
    }

    // New Card
    function newCard(
        uint cardId_,
        uint level_,
        uint price_,
        string calldata tokenURI_
    ) public onlyOwner {
        require(
            cardId_ != 0 && cardInfoes[cardId_].cardId == 0,
            "MSW: wrong cardId"
        );

        cardInfoes[cardId_] = CardInfo({
            cardId: cardId_,
            currentAmount: 0,
            level: level_,
            price: price_,
            tokenURI: tokenURI_
        });
        emit NewCard(cardId_);
    }

    // mint
    function mint(
        address to_,
        uint cardId_,
        uint amount_
    ) public returns (bool) {
        require(cardInfoes[cardId_].cardId != 0, "MSW: wrong cardId");

        require(
            minters[msg.sender][cardId_] >= amount_ || superMinters[msg.sender],
            "MSW: amount out of minter"
        );
        if (!superMinters[msg.sender]) {
            minters[msg.sender][cardId_] -= amount_;
        }

        for (uint i = 0; i < amount_; i++) {
            uint tokenId = getNextTokenId();
            // cardOwners[tokenId] = to_;
            cardIdMap[tokenId] = cardId_;
            cardInfoes[cardId_].currentAmount++;
            _safeMint(to_, tokenId);
            emit Mint(msg.sender, cardId_, tokenId);
        }
        return true;
    }

    // upgrade
    function upgrade(uint tokenId_, uint toCardId_) public returns (bool) {
        require(cardInfoes[toCardId_].cardId != 0, "MSW: wrong cardId");
        // require(cardOwners[tokenId_] == msg.sender, "MSW: not owner");
        uint _oldCardId = cardIdMap[tokenId_];
        require(_oldCardId < toCardId_, "MSW: wrong lv");

        uint diff = cardInfoes[toCardId_].price - cardInfoes[_oldCardId].price;

        cardIdMap[tokenId_] = toCardId_;

        cardInfoes[_oldCardId].currentAmount -= 1;
        cardInfoes[toCardId_].currentAmount += 1;

        IERC20(USDT).transferFrom(msg.sender, WALLET, diff);

        emit Upgrade(msg.sender, tokenId_, toCardId_);
        return true;
    }

    // view
    function getNowTokenId() public view returns (uint) {
        return _tokenIds.current();
    }

    // get Next TokenId
    function getNextTokenId() internal returns (uint) {
        _tokenIds.increment();
        uint ids = _tokenIds.current();
        return ids;
    }

    // check baseURI
    function _myBaseURI() internal view returns (string memory) {
        return myBaseURI;
    }

    // check this tokenid's tokenURIs
    function tokenURI(
        uint tokenId_
    ) public view override(ERC721) returns (string memory) {
        require(_exists(tokenId_), "MSW: nonexistent token");

        return
            string(
                abi.encodePacked(
                    _myBaseURI(),
                    "/",
                    cardInfoes[cardIdMap[tokenId_]].tokenURI
                )
            );
    }

    function tokenOfOwnerForAll(
        address addr_
    ) public view returns (uint[] memory, uint[] memory) {
        uint len = balanceOf(addr_);
        uint id;
        uint[] memory _TokenIds = new uint[](len);
        uint[] memory _CardIds = new uint[](len);
        for (uint i = 0; i < len; i++) {
            id = tokenOfOwnerByIndex(addr_, i);
            _TokenIds[i] = id;
            _CardIds[i] = cardIdMap[id];
        }
        return (_TokenIds, _CardIds);
    }
}

