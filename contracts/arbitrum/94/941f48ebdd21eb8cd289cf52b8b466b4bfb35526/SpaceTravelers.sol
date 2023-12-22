// SPDX-License-Identifier: MIT

/**

https://t.me/arbistellar
https://twitter.com/ArbiStellar
https://arbistellar.xyz/

*/

pragma solidity ^0.8.0;

import "./ERC721Enumerable.sol";
import "./Ownable.sol";
import "./Pausable.sol";
import "./Counters.sol";
import "./LibPart.sol";
import "./LibRoyalties.sol";
import "./RoyaltiesImpl.sol";
import "./STLR.sol";

contract SpaceTravelers is ERC721Enumerable, Ownable, RoyaltiesImpl, Pausable {
    using Strings for uint256;
    using Counters for Counters.Counter;

    STLR stlr;

    mapping(address => bool) controllers;
    string public baseURI;
    uint256 public startTime;
    string public baseExtension = ".png";
    uint256 public priceMint = 10 ether;
    uint256 public maxMintAmountPerTx = 20;
    uint256 public maxMintAmountPerWallet = 50;
    uint256 public constant percentHuman = 60;
    uint256 public constant percentRobot = 30;
    uint256 public constant percentAlien = 10;
    uint256 public amountHuman = 0;
    uint256 public amountRobot = 0;
    uint256 public amountAlien = 0;
    uint256 private numberCounter = 0;
    uint16 public maxSupply = 999;
    uint8[] public race;
    address public marketingFeeReceiver;

    //tokenId
    Counters.Counter public _tokenIdCounter;

    // royalties
    bytes4 private constant _INTERFACE_ID_ERC2981 = 0x2a55205a;
    address public royaltiesAddress;
    address payable royaltiesAddressPayable = payable(royaltiesAddress);

    constructor(string memory _baseUri, address _marketingFeeReceiver, uint _startTime, address _stlr) ERC721("SPACE_TRAVELERS", "STLS")
    {
        setBaseURI(_baseUri);
        setMarketingFeeReceiver(_marketingFeeReceiver);
        setAddressRoyalties(_marketingFeeReceiver);
        setStartTime(_startTime);
        _tokenIdCounter.increment();
        stlr = STLR(payable(_stlr));
    }

    function mint(address to, uint256 mintAmount)
    public
    whenNotPaused
    {
        uint256 supply =  _tokenIdCounter.current();
        require(block.timestamp >= startTime, "Mint is not started");
        require(mintAmount > 0, "Please mint at least one");
        require(mintAmount <= maxMintAmountPerTx, "Leave some of those for everybody else");
        require(balanceOf(to) + mintAmount <= maxMintAmountPerWallet, "Limit per wallet");
        require(supply + mintAmount <= maxSupply, "Limit reached");

        uint256 _balance = stlr.balanceOf(msg.sender);
        require(_balance >= mintAmount * priceMint , "Insufficient amount in $STLR to buy STLS");

        for (uint256 i = 1; i <= mintAmount; i++) {
            uint256 tokenIdMint =  _tokenIdCounter.current();
            uint random = _random(100);
            if (random <= 60){
                // Human
                race.push(1);
                amountHuman ++;
            }
            else if (random <= 90){
                // robot
                race.push(2);
                amountRobot ++;
            }
            else {
                // Alien
                race.push(3);
                amountAlien ++;
            }

            _safeMint(to, tokenIdMint);
            // royalties fixed 8%
            setRoyalties(tokenIdMint, royaltiesAddressPayable, 800);
            _tokenIdCounter.increment();
        }

        // Burn the tokens used to mint the NFT
        uint256 fee = (mintAmount * priceMint) * 20 / 100;
        stlr.burn(msg.sender, (mintAmount * priceMint));
        stlr.mint(address(marketingFeeReceiver), fee);
    }

    function walletOfOwner(address _owner)
    public
    view
    returns (uint256[] memory)
    {
        uint256 ownerTokenCount = balanceOf(_owner);
        uint256[] memory tokenIds = new uint256[](ownerTokenCount);
        for (uint256 i; i < ownerTokenCount; i++) {
            tokenIds[i] = tokenOfOwnerByIndex(_owner, i);
        }
        return tokenIds;
    }

    function tokenURI(uint256 tokenId)
    public
    view
    virtual
    override
    returns (string memory)
    {
        uint256 race = getRace(tokenId);
        string memory image = string(abi.encodePacked(baseURI, uint2str(race), baseExtension));
        string memory attributes = string(abi.encodePacked("\"attributes\":[{\"trait_type\":\"Race","\",\"value\":\"", getRaceName(race),"\"}]"));
        string memory json = base64(
            bytes(string(
                abi.encodePacked(
                    '{',
                    '"name": " Space Travelers ', uint2str(tokenId) , '"',
                    ', "edition":"', uint2str(tokenId), '"',
                    ', "image":"', image, '"',
                    ',',attributes,
                    '}'
                )
            ))
        );
        return string(abi.encodePacked('data:application/json;base64,', json));
    }

    function _baseURI()
    internal
    view
    virtual
    override
    returns (string memory)
    {
        return baseURI;
    }

    function getRace(uint256 tokenId) public view returns (uint8) {
        return (race[tokenId-1]);
    }

    function getRaceName(uint256 race) public view returns (string memory) {
        if (race == 1) return "Human";
        else if (race == 2) return "Robot";
        else if (race == 3) return "Alien";
        else return "this race does not exist!";
    }

    function getRaces(uint256[] memory tokenIds) public view returns (uint8[] memory) {
        uint8[] memory races = new uint8[](tokenIds.length);
        for (uint256 i = 0; i < tokenIds.length; i++) {
            races[i] = getRace(tokenIds[i]);
        }
        return races;
    }

    function setRoyalties(uint tokenId, address payable royaltiesRecipientAddress, uint96 percentageBasisPoints)
    private
    {
        LibPart.Part[] memory royalties = new LibPart.Part[](1);
        royalties[0].value = percentageBasisPoints;
        royalties[0].account = royaltiesRecipientAddress;
        _saveRoyalties(tokenId, royalties);
    }

    function royaltyInfo(uint256 _tokenId, uint256 _salePrice)
    external
    view
    returns (address receiver, uint256 royaltyAmount)
    {
        LibPart.Part[] memory _royalties = royalties[_tokenId];
        if (_royalties.length > 0) {
            return (_royalties[0].account, (_salePrice * _royalties[0].value) / 10000);
        }
    }

    function supportsInterface(bytes4 interfaceId)
    public
    view
    virtual
    override(ERC721Enumerable)
    returns (bool)
    {
        if (interfaceId == LibRoyalties._INTERFACE_ID_ROYALTIES) {
            return true;
        }

        if (interfaceId == _INTERFACE_ID_ERC2981) {
            return true;
        }
        return super.supportsInterface(interfaceId);
    }

    function transferFrom(address from, address to, uint256 tokenId)
    public
    virtual
    override
    {
        require(_isApprovedOrOwner(msg.sender, tokenId), "ERC721: transfer caller is not owner nor approved");
        _transfer(from, to, tokenId);
    }

    function _random(uint value)
    internal
    returns(uint)
    {
        return uint(keccak256(abi.encodePacked(block.difficulty, block.timestamp, numberCounter++))) % value;
    }

    // --- For Admin ---
    function addController(address controller)
    external
    onlyOwner
    {
        controllers[controller] = true;
    }

    function setStartTime(uint256 _newStartTime)
    public
    onlyOwner
    {
        startTime = _newStartTime;
    }

    function setAddressRoyalties (address _newRoyaltiesAddress)
    public
    onlyOwner
    {
        royaltiesAddressPayable = payable(_newRoyaltiesAddress);
    }

    function setMaxMintAmountPerTx(uint256 _newMaxMintAmountPerTx)
    public
    onlyOwner
    {
        maxMintAmountPerTx = _newMaxMintAmountPerTx;
    }

    function setMaxMintAmountPerWallet(uint256 _maxMintAmountPerWallet)
    public
    onlyOwner {
        maxMintAmountPerWallet = _maxMintAmountPerWallet;
    }

    function setPrice(uint256 _newPrice)
    public
    onlyOwner
    {
        priceMint = _newPrice;
    }

    function setBaseURI(string memory _newBaseURI)
    public
    onlyOwner
    {
        baseURI = _newBaseURI;
    }

    function setBaseExtension(string memory _newBaseExtension)
    public
    onlyOwner {
        baseExtension = _newBaseExtension;
    }

    function removeController(address controller)
    external
    onlyOwner
    {
        controllers[controller] = false;
    }

    function setPaused(bool _paused)
    external
    onlyOwner
    {
        if (_paused) _pause();
        else _unpause();
    }

    function setNFTSupply(uint16 _maxSupply) public onlyOwner {
        maxSupply = _maxSupply;
    }

    function setMarketingFeeReceiver(address _marketingFeeReceiver) public onlyOwner {
        marketingFeeReceiver = _marketingFeeReceiver;
    }

    // Override functions
    function approve(address account, address to, uint256 tokenId)
    external
    {
        address owner = ERC721.ownerOf(tokenId);
        require(to != owner, "ERC721: approval to current owner");

        require(
            account == owner || isApprovedForAll(owner, _msgSender()),
            "ERC721: approve caller is not owner nor approved for all"
        );

        _approve(to, tokenId);
    }

    //LIB
    function uint2str(uint _i) internal pure returns (string memory _uintAsString) {
        if (_i == 0) {
            return "0";
        }
        uint j = _i;
        uint len;
        while (j != 0) {
            len++;
            j /= 10;
        }
        bytes memory str = new bytes(len);
        uint k = len;
        while (_i != 0) {
            k = k-1;
            uint8 temp = (48 + uint8(_i - _i / 10 * 10));
            bytes1 b1 = bytes1(temp);
            str[k] = b1;
            _i /= 10;
        }
        return string(str);
    }

    string internal constant TABLE = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';

    function base64(bytes memory data) internal pure returns (string memory) {
        if (data.length == 0) return '';

        // load the table into memory
        string memory table = TABLE;

        // multiply by 4/3 rounded up
        uint256 encodedLen = 4 * ((data.length + 2) / 3);

        // add some extra buffer at the end required for the writing
        string memory result = new string(encodedLen + 32);

        assembly {
        // set the actual output length
            mstore(result, encodedLen)

        // prepare the lookup table
            let tablePtr := add(table, 1)

        // input ptr
            let dataPtr := data
            let endPtr := add(dataPtr, mload(data))

        // result ptr, jump over length
            let resultPtr := add(result, 32)

        // run over the input, 3 bytes at a time
            for {} lt(dataPtr, endPtr) {}
            {
                dataPtr := add(dataPtr, 3)

            // read 3 bytes
                let input := mload(dataPtr)

            // write 4 characters
                mstore(resultPtr, shl(248, mload(add(tablePtr, and(shr(18, input), 0x3F)))))
                resultPtr := add(resultPtr, 1)
                mstore(resultPtr, shl(248, mload(add(tablePtr, and(shr(12, input), 0x3F)))))
                resultPtr := add(resultPtr, 1)
                mstore(resultPtr, shl(248, mload(add(tablePtr, and(shr(6, input), 0x3F)))))
                resultPtr := add(resultPtr, 1)
                mstore(resultPtr, shl(248, mload(add(tablePtr, and(input, 0x3F)))))
                resultPtr := add(resultPtr, 1)
            }

        // padding with '='
            switch mod(mload(data), 3)
            case 1 {mstore(sub(resultPtr, 2), shl(240, 0x3d3d))}
            case 2 {mstore(sub(resultPtr, 1), shl(248, 0x3d))}
        }
        return result;
    }

}


