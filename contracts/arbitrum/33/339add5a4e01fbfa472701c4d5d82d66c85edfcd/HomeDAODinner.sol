// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./ERC721.sol";

contract HomeDAODinner is ERC721 {
    uint256 private _currentTokenId = 0;
    uint private maxSupply;
    address private owner;
    string private baseUri;

    constructor(
        string memory _name,
        string memory _symbol,
        address _owner,
        string memory _baseUri,
        uint _maxSupply
    ) ERC721(_name, _symbol) {
        owner = _owner;
        baseUri = _baseUri;
        maxSupply = _maxSupply;
    }

    /**
     * @dev Mints a token to an address with a tokenURI.
     * @param _to address of the future owner of the token
     */
    function mintTo(address _to) external {
        require(msg.sender == owner, "Only owner can mint");
        require(_currentTokenId < maxSupply, "Max supply reached");
        require(balanceOf(_to) < 1, "Only one token per address");
        uint256 newTokenId = _getNextTokenId();
        _mint(_to, newTokenId);
        _incrementTokenId();
    }

    /**
     * @dev See {IERC721-transferFrom}.
     */
    function transferFrom(
        address from,
        address to,
        uint256 tokenId
    ) public override {
        revert("Non-transferable token");
    }

    /**
     * @dev See {IERC721-safeTransferFrom}.
     */
    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId
    ) public override {
        revert("Non-transferable token");
    }

    /**
     * @dev See {IERC721-safeTransferFrom}.
     */
    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId,
        bytes memory data
    ) public override {
        revert("Non-transferable token");
    }

    /**
     * @dev calculates the next token ID based on value of _currentTokenId
     * @return uint256 for the next token ID
     */
    function _getNextTokenId() private view returns (uint256) {
        return _currentTokenId + 1;
    }

    /**
     * @dev increments the value of _currentTokenId
     */
    function _incrementTokenId() private {
        _currentTokenId++;
    }

    /**
     * @dev returns the baseURI for the token
     * @return string for the token URI
     */
    function tokenURI(uint256 _tokenId)
        public
        view
        virtual
        override
        returns (string memory)
    {
        string memory baseURI = _baseURI();
        return baseURI;
    }

    /**
     * @dev Base URI for computing {tokenURI}. If set, the resulting URI for each
     * token will be the concatenation of the `baseURI` and the `tokenId`. Empty
     * by default, can be overridden in child contracts.
     */
    function _baseURI() internal view override returns (string memory) {
        return baseUri;
    }

    /**
     * @dev changes the base URI for the tokens
     */
    function changeBaseUri(string memory _baseUri) external {
        require(msg.sender == owner, "Only owner can change base URI");
        baseUri = _baseUri;
    }

    /**
     * @dev self destructs the contract
     */
    function burnAll() external {
        require(msg.sender == owner, "Only owner can burn contract");
        address payable payableOwner = payable(owner);
        selfdestruct(payableOwner);
    }
}

