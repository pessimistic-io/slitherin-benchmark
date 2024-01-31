// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

//-----------------------------------------------------------------------------
// geneticchain.io - NextGen Generative NFT Platform
//-----------------------------------------------------------------------------
 /*\_____________________________________________________________   .¿yy¿.   __
 MMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMM```````/MMM\\\\\  \\$$$$$$S/  .
 MMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMM``   `/  yyyy    ` _____J$$$^^^^/%#//
 MMMMMMMMMMMMMMMMMMMYYYMMM````      `\/  .¿yü  /  $ùpüüü%%% | ``|//|` __
 MMMMMYYYYMMMMMMM/`     `| ___.¿yüy¿.  .d$$$$  /  $$$$SSSSM |   | ||  MMNNNNNNM
 M/``      ``\/`  .¿ù%%/.  |.d$$$$$$$b.$$$*°^  /  o$$$  __  |   | ||  MMMMMMMMM
 M   .¿yy¿.     .dX$$$$$$7.|$$$$"^"$$$$$$o`  /MM  o$$$  MM  |   | ||  MMYYYYYYM
   \\$$$$$$S/  .S$$o"^"4$$$$$$$` _ `SSSSS\        ____  MM  |___|_||  MM  ____
  J$$$^^^^/%#//oSSS`    YSSSSSS  /  pyyyüüü%%%XXXÙ$$$$  MM  pyyyyyyy, `` ,$$$o
 .$$$` ___     pyyyyyyyyyyyy//+  /  $$$$$$SSSSSSSÙM$$$. `` .S&&T$T$$$byyd$$$$\
 \$$7  ``     //o$$SSXMMSSSS  |  /  $$/&&X  _  ___ %$$$byyd$$$X\$`/S$$$$$$$S\
 o$$l   .\\YS$$X>$X  _  ___|  |  /  $$/%$$b.,.d$$$\`7$$$$$$$$7`.$   `"***"`  __
 o$$l  __  7$$$X>$$b.,.d$$$\  |  /  $$.`7$$$$$$$$%`  `*+SX+*|_\\$  /.     ..\MM
 o$$L  MM  !$$$$\$$$$$$$$$%|__|  /  $$// `*+XX*\'`  `____           ` `/MMMMMMM
 /$$X, `` ,S$$$$\ `*+XX*\'`____  /  %SXX .      .,   NERV   ___.¿yüy¿.   /MMMMM
  7$$$byyd$$$>$X\  .,,_    $$$$  `    ___ .y%%ü¿.  _______  $.d$$$$$$$S.  `MMMM
  `/S$$$$$$$\\$J`.\\$$$ :  $\`.¿yüy¿. `\\  $$$$$$S.//XXSSo  $$$$$"^"$$$$.  /MMM
 y   `"**"`"Xo$7J$$$$$\    $.d$$$$$$$b.    ^``/$$$$.`$$$$o  $$$$\ _ 'SSSo  /MMM
 M/.__   .,\Y$$$\\$$O` _/  $d$$$*°\ pyyyüüü%%%W $$$o.$$$$/  S$$$. `  S$To   MMM
 MMMM`  \$P*$$X+ b$$l  MM  $$$$` _  $$$$$$SSSSM $$$X.$T&&X  o$$$. `  S$To   MMM
 MMMX`  $<.\X\` -X$$l  MM  $$$$  /  $$/&&X      X$$$/$/X$$dyS$$>. `  S$X%/  `MM
 MMMM/   `"`  . -$$$l  MM  yyyy  /  $$/%$$b.__.d$$$$/$.'7$$$$$$$. `  %SXXX.  MM
 MMMMM//   ./M  .<$$S, `` ,S$$>  /  $$.`7$$$$$$$$$$$/S//_'*+%%XX\ `._       /MM
 MMMMMMMMMMMMM\  /$$$$byyd$$$$\  /  $$// `*+XX+*XXXX      ,.      .\MMMMMMMMMMM
 GENETIC/MMMMM\.  /$$$$$$$$$$\|  /  %SXX  ,_  .      .\MMMMMMMMMMMMMMMMMMMMMMMM
 CHAIN/MMMMMMMM/__  `*+YY+*`_\|  /_______//MMMMMMMMMMMMMMMMMMMMMMMMMMM/-/-/-\*/
//-----------------------------------------------------------------------------
// Genetic Chain: KlabelKholosh - Theta
//-----------------------------------------------------------------------------
// Author: papaver (@papaver42)
//-----------------------------------------------------------------------------

import "./Ownable.sol";
import "./ERC2981.sol";
import "./ERC721.sol";
import "./IERC721Enumerable.sol";
import "./ECDSA.sol";
import "./Strings.sol";

//------------------------------------------------------------------------------
// helper contracts
//------------------------------------------------------------------------------

/**
 * Expose reference contract.
 */
interface IGenArt {
  function tokenHash(uint256 tokenId) external view returns (bytes32);
  function state(uint256 tokenId) external view returns (int64 flutA, int64 lnThk, bool moving);
}

//------------------------------------------------------------------------------
// KlabelKholosh - Theta
//------------------------------------------------------------------------------

/**
 * @title GeneticChain - Project #19? - KlabelKholosh - Theta
 */
contract Theta is
    ERC721,
    ERC2981,
    Ownable
{
    using ECDSA for bytes32;

    //-------------------------------------------------------------------------
    // structs
    //-------------------------------------------------------------------------

    struct IpfsAsset {
        string name;
        string hash;
    }

    //-------------------------------------------------------------------------

    struct ArtState {
        uint16 spd;
        uint8  _set;
    }

    //-------------------------------------------------------------------------
    // events
    //-------------------------------------------------------------------------

    event StateChange(address indexed owner, uint256 tokenId, ArtState state);

    //-------------------------------------------------------------------------
    // constants
    //-------------------------------------------------------------------------

    // erc721 metadata
    string constant private __name   = "Theta";
    string constant private __symbol = "THETA";

    // genart contract reference
    address private immutable _artLink;

    // mint info
    uint256 private _totalSupply;

    // contract info
    string private _contractUri;

    // token info
    string private _baseUri;
    string private _ipfsHash;

    // art code
    string public code;
    IpfsAsset[] public libraries;

    // token state
    mapping(uint256 => ArtState) _state;

    //-------------------------------------------------------------------------
    // modifiers
    //-------------------------------------------------------------------------

    modifier validTokenId(uint256 tokenId) {
        require(_exists(tokenId), "invalid token");
        _;
    }

    //-------------------------------------------------------------------------

    modifier approvedOrOwner(address operator, uint256 tokenId) {
        require(_isApprovedOrOwner(operator, tokenId), "not token owner nor approved");
        _;
    }

    //-------------------------------------------------------------------------

    modifier ownsLink(uint256 tokenId) {
        require(IERC721(_artLink).ownerOf(tokenId) == msg.sender, "invalid link");
        _;
    }

    //-------------------------------------------------------------------------
    // ctor
    //-------------------------------------------------------------------------

    constructor(
        address artLink_,
        IpfsAsset memory lib_,
        string memory baseUri_,
        string memory contractUri_,
        address royaltyAddress_)
        ERC721(__name, __symbol)
    {
        // uris
        _baseUri     = baseUri_;
        _contractUri = contractUri_;

        // reference to previous art contract
        _artLink = artLink_;

        // add library reference
        addLibrary(lib_.name, lib_.hash);

        // royalty
        _setDefaultRoyalty(royaltyAddress_, 1000);
    }

    //-------------------------------------------------------------------------
    // accessors
    //-------------------------------------------------------------------------

    function setUriIpfsHash(string memory hash)
        public
        onlyOwner
    {
        if (bytes(hash).length == 0) {
            delete _ipfsHash;
        } else {
            _ipfsHash = hash;
        }
    }

    //-------------------------------------------------------------------------

    function setBaseURI(string memory baseUri)
        public
        onlyOwner
    {
        _baseUri = baseUri;
    }

    //-------------------------------------------------------------------------

    /**
     * Get total minted.
     */
    function totalSupply()
        public view
        returns (uint256)
    {
        return _totalSupply;
    }

    //-------------------------------------------------------------------------

    /**
     * Get max supply of collection.
     *   Warning: This should NOT be called from within the contract.
     *    References unefficient code implementation of IERC721Enumerable.
     */
    function maxSupply()
        public view
        returns (uint256)
    {

        return IERC721Enumerable(_artLink).totalSupply();
    }

    //-------------------------------------------------------------------------

    function setCode(string memory code_)
        public
        onlyOwner
    {
        code = code_;
    }

    //-------------------------------------------------------------------------

    function addLibrary(string memory name, string memory hash)
        public
        onlyOwner
    {
        IpfsAsset memory lib = IpfsAsset(name, hash);
        libraries.push(lib);
    }

    //-------------------------------------------------------------------------

    function removeLibrary(uint256 index)
        public
        onlyOwner
    {
        require(index < libraries.length);
        libraries[index] = libraries[libraries.length - 1];
        libraries.pop();
    }

    //-------------------------------------------------------------------------

    function getLibraryCount()
        public view
        returns (uint256)
    {
        return libraries.length;
    }

    //-------------------------------------------------------------------------

    function getLibraries()
        public view
        returns (IpfsAsset[] memory)
    {
        IpfsAsset[] memory libs = new IpfsAsset[](libraries.length);
        for (uint256 i = 0; i < libraries.length; ++i) {
          IpfsAsset storage lib = libraries[i];
          libs[i] = lib;
        }
        return libs;
    }

    //-------------------------------------------------------------------------
    // ERC2981 - NFT Royalty Standard
    //-------------------------------------------------------------------------

    /**
     * @dev Update royalty receiver + basis points.
     */
    function setRoyaltyInfo(address receiver, uint96 feeBasisPoints)
        external
        onlyOwner
    {
        _setDefaultRoyalty(receiver, feeBasisPoints);
    }

    //-------------------------------------------------------------------------
    // IERC165 - Introspection
    //-------------------------------------------------------------------------

    function supportsInterface(bytes4 interfaceId)
        public view
        override(ERC721, ERC2981)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    //-------------------------------------------------------------------------
    // ERC721Metadata
    //-------------------------------------------------------------------------

    function baseTokenURI()
        public view
        returns (string memory)
    {
        return _baseUri;
    }

    //-------------------------------------------------------------------------

    /**
     * @dev Returns uri of a token.  Not guarenteed token exists.
     */
    function tokenURI(uint256 tokenId)
        override
        public view
        returns (string memory)
    {
        return bytes(_ipfsHash).length == 0
            ? string(abi.encodePacked(
                baseTokenURI(), "/", Strings.toString(tokenId)))
            : string(abi.encodePacked(
                baseTokenURI(),
                    "/", _ipfsHash,
                    "/", Strings.toString(tokenId)));
    }

    //-------------------------------------------------------------------------
    // minting
    //-------------------------------------------------------------------------

    /**
     * Claim single token.
     */
    function claim(uint256 tokenId)
        external
        ownsLink(tokenId)
    {
        require(!_exists(tokenId), "token claimed");

        // track supply
        unchecked {
          _totalSupply += 1;
        }

        // mint token
        _safeMint(msg.sender, tokenId);
    }

    //-------------------------------------------------------------------------
    // generative
    //-------------------------------------------------------------------------

    /**
     * @dev Returns tokens generative hash.
     */
    function tokenHash(uint256 tokenId)
        public view
        validTokenId(tokenId)
        returns (bytes32)
    {
        return IGenArt(_artLink).tokenHash(tokenId);
    }

    //-------------------------------------------------------------------------
    // state
    //-------------------------------------------------------------------------

    function state(uint256 tokenId)
        public
        view
        validTokenId(tokenId)
        returns (int64 flutA, uint16 spd, bool moving)
    {
        if (_state[tokenId]._set == 0) {
            spd = 150;
        } else {
            spd = _state[tokenId].spd;
        }

        // retreive state from artlink
        (flutA, , moving) = IGenArt(_artLink).state(tokenId);
    }

    //-------------------------------------------------------------------------

    /**
     * Updates state of token, only owner or approved is allowed.
     * @param tokenId - token to update state on
     * @param spd - speed of animation; 0-300
     *
     * Emits a {StateUpdated} event.
     */
    function updateState(uint256 tokenId, uint16 spd)
        external
        approvedOrOwner(msg.sender, tokenId)
    {
        require(0 <= spd && spd <= 300, "invalid spd");
        _state[tokenId].spd  = spd;
        _state[tokenId]._set = 1;

        emit StateChange(msg.sender, tokenId, _state[tokenId]);
    }

    //-------------------------------------------------------------------------
    // contractUri
    //-------------------------------------------------------------------------

    function setContractURI(string memory contractUri)
        external
        onlyOwner
    {
        _contractUri = contractUri;
    }

    //-------------------------------------------------------------------------

    function contractURI()
        public view
        returns (string memory)
    {
        return _contractUri;
    }

}

