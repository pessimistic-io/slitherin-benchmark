//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ERC721URIStorage.sol";
import "./ERC721Enumerable.sol";
import { Strings } from "./Strings.sol";


import "./MYPAPI.sol";
import { Base64 } from "./Base64.sol";

import "./UserAccessible.sol";

import { Constants } from "./MYPConstants.sol";
import { UserPunk } from "./MYP.sol";

/**
................................................
................................................
................................................
................................................
...................';::::::;'.';'...............
.............';'.':kNWWWWWWNkcod;...............
.............oXkckNWMMMMMMMMWNkc'.';'...........
.........'::ckWWWWMMMMMMMMMMMMWNkcoxo:'.........
.........;xKWWMMMMWXKNMMMMMMMMMMWNklkXo.........
.........'cOWMMMMN0kxk0XWWXK0KNWMMWWKk:.........
.......':okKWMMMWOldkdlkNNkcccd0NMMWOc'.........
.......;dolOWMWX0d:;::ckXXkc:;;:lkKWKko:'.......
.......':okKWN0dc,.',;:dOOkd:.''..lNOlod:.......
.....':kNklONx;;:,.';:::ccdkc.',. lWMNo.........
.....:xkOKWWWl..:::::::::::c:::;. lWMWk:'.......
.........dWMWl .:::::::;;;;:::::. lNXOkx;.......
. .....':okkk; .;::::::,'',:::::. ;xdc'.........
.......:d:...  .;::::;,,,,,,;:::.  .:d:.........
.. ..........  .';:::,'....',:;'.  .............
..............   .,,,;::::::;'.    .............
..............    .  .''''''.   ................
..............   ....          .................
..............   .;,....    . ..................
..............   .;:::;.    ....................

               Made with <3 from
             @author @goldendilemma

*/

contract MYPNFT is 
  ERC721Enumerable,
  UserAccessible
{

  MYPAPI public api;

  mapping (bytes32 => bool) punkIsMinted;
  mapping (uint => UserPunk) punkAttributes;
  mapping (uint => address) punkCreator;

  mapping (uint => bool) public banned;
  string public bannedTokenUri;

  bool public frozen;

  string public nftName;
  string public nftDescription = 'Mint Your Punk is an experiment by @goldendilemma';

  uint public tokenCount = 0;

  bool public includeMeta = true;
  string public svgHeader;
  
  string public animationUrl = '';
  bool showAnimationUrl = false;

  string public overrideUrl = '';
  bool showOverrideUrl = false;

  event PunkMint(address to, uint256 tokenId, uint256 tokenCount);

  // opensea
  event BatchMetadataUpdate(uint256 _fromTokenId, uint256 _toTokenId);
  event MetadataUpdate(uint256 _tokenId);

  constructor(
    string memory _nftName, 
    string memory _nftTicker, 
    address _userAccess
  ) 
    ERC721 (_nftName, _nftTicker) 
    UserAccessible(_userAccess)
  {
    nftName = _nftName;
  }

  modifier requireAPI() {
    require(address(api) != address(0), "API_NOT_SETUP");
    _;
  }
  
  modifier tokenExists (uint tokenId) {
    require(_exists(tokenId), "ERC721: invalid token ID"); 
    _;
  }

  modifier notFrozen () {
    require(!frozen, "CONTRACT_FROZEN");
    _;
  }

  function attributesOf(uint256 tokenId) public view returns (UserPunk memory) {
    return punkAttributes[tokenId];
  }

  function setBanStatus (uint tokenId, bool newState) public notFrozen onlyAdmin {
    banned[tokenId] = newState;
    emit MetadataUpdate(tokenId);
  }

  function setBannedTokenUri (string memory _bannedTokenUri) public notFrozen onlyAdmin {
    bannedTokenUri = _bannedTokenUri;
    emit BatchMetadataUpdate(0, type(uint256).max);
  }

  function setShowOverrideUrl (bool newState) public notFrozen onlyAdmin { 
    showOverrideUrl = newState; 
    emit BatchMetadataUpdate(0, type(uint256).max);
  }
  function setOverrideUrl(string memory newUrl) public notFrozen onlyAdmin { 
    overrideUrl = newUrl; 
    emit BatchMetadataUpdate(0, type(uint256).max);
  }

  function setShowAnimationUrl (bool newState) public notFrozen onlyAdmin { 
    showAnimationUrl = newState; 
    emit BatchMetadataUpdate(0, type(uint256).max);
  }
  function setAnimationUrl(string memory newAnimation) public notFrozen onlyAdmin { 
    animationUrl = newAnimation; 
    emit BatchMetadataUpdate(0, type(uint256).max);
  }
  function setAPIContract(address apiContract) public notFrozen onlyAdmin { api = MYPAPI(apiContract); }
  function setIncludeMeta (bool newState) public notFrozen onlyAdmin { 
    includeMeta = newState;
    emit BatchMetadataUpdate(0, type(uint256).max);
  }
  function disableName (uint tokenId) public notFrozen onlyAdmin { 
    punkAttributes[tokenId].isNamed = false; 
    emit MetadataUpdate(tokenId);
  }
  function setName(uint tokenId, string memory newName, bool isNamed) public notFrozen onlyAdmin {
    UserPunk storage p = punkAttributes[tokenId];
    p.isNamed = isNamed;
    p.name = newName;
    emit MetadataUpdate(tokenId);
  }
  function setTokenName (string memory newName) public notFrozen onlyAdmin { 
    nftName = newName; 
    emit BatchMetadataUpdate(0, type(uint256).max);
  }
  function setTokenDescription (string memory newDescription) public notFrozen onlyAdmin { 
    nftDescription = newDescription; 
    emit BatchMetadataUpdate(0, type(uint256).max);
  }
  function setSVGHeader (string memory newHeader) public notFrozen onlyAdmin {
    svgHeader = newHeader;
    emit BatchMetadataUpdate(0, type(uint256).max);
  }

  // WARNING: makes all punks immutable, even for admins, the final step.
  function freeze () public onlyAdmin { frozen = true; }

  function mintYourPunk (
    address to,
    address creator,
    UserPunk calldata punk
  ) public onlyRole(Constants.MYP_MINTER) {
    _mintPunk(to, creator, punk);
  }

  function creatorOf (uint tokenId) 
    public 
    view 
    tokenExists(tokenId)
    returns (address) 
  {
    return punkCreator[tokenId];
  }

  function isUnique (
    uint16[] memory attributeIndexes,
    uint8[][] memory fillIndexes
  )
    public
    view
    requireAPI
    returns (bool)
  {
    bytes32 punkId = api.getPunkId(attributeIndexes, fillIndexes);
    return !punkIsMinted[punkId];
  }
  

  function _mintPunk (
    address to,
    address creator,
    UserPunk calldata punk
  ) 
    private 
    notFrozen
    requireAPI
  {
    
    api.validatePunk(punk.genderIndex, punk.typeIndex, punk.attributeIndexes, punk.fillIndexes);

    bytes32 punkId = api.getPunkId(punk.attributeIndexes, punk.fillIndexes);
    require(!punkIsMinted[punkId], "NON_UNIQUE_PUNK");

    uint256 newTokenId = tokenCount;

    _safeMint(to, newTokenId);

    punkIsMinted[punkId] = true;
    punkAttributes[newTokenId] = punk;
    punkCreator[newTokenId] = creator;
    tokenCount++;

    emit PunkMint(to, newTokenId, tokenCount);
  }

  function getAnimationUrl (uint tokenId) 
  internal view
  returns (string memory) 
  {
    return string(abi.encodePacked(animationUrl, Strings.toString(tokenId)));
  }

  function tokenURI(uint256 tokenId) 
    override
    public
    view 
    tokenExists(tokenId)
  returns (string memory) 
  {

    if (banned[tokenId]) return bannedTokenUri;
    if (showOverrideUrl) return string(abi.encodePacked(overrideUrl, Strings.toString(tokenId), '.json'));

    UserPunk memory p = punkAttributes[tokenId];

    MYPunk memory punk = api.renderPunk(p);

    string memory svg = string(abi.encodePacked(
      svgHeader,
      '<style>.eo {fill-rule:evenodd;clip-rule:evenodd;}</style>',
      punk.svg,
      '</svg>'
    ));
    
    string memory tokenName = p.isNamed
      ? p.name
      : string(abi.encodePacked(nftName, ' #', Strings.toString(tokenId)));
    string memory image = string(abi.encodePacked("data:image/svg+xml;base64,", Base64.encode(bytes(svg))));
    bytes memory metaProps = abi.encodePacked(
      ',"ID": ', Strings.toString(tokenId), ',',
      '"Creator":"', Strings.toHexString(uint256(uint160(punkCreator[tokenId])), 20), '"'
    );
    bytes memory properties = abi.encodePacked(
      punk.jsonAttributes,
      includeMeta
        ? metaProps
        : bytes("")
    );
    string memory encodedMetaData = Base64.encode(bytes(string(abi.encodePacked(
      '{ "name": "', tokenName, '",',
        '"description": "', nftDescription,'",',
        '"image": "', image, '",',
        showAnimationUrl 
          ? string(abi.encodePacked('"animation_url": "', getAnimationUrl(tokenId), '",')) 
          : '',
        '"properties": {', 
          properties,
        '} }'
    ))));

    string memory tokenUri = string(abi.encodePacked(
      "data:application/json;base64,",
      encodedMetaData
    ));

    return tokenUri;
  }
    
}

