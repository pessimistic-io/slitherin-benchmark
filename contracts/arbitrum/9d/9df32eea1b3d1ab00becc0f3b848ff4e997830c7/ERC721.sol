// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./ERC721Enumerable.sol";
import "./ReentrancyGuard.sol";
import "./AccessControl.sol";
import "./Ownable.sol";
import "./ERC721Royalty.sol";
import "./MintCounter.sol";

contract ERC721DEEP  is ERC721Enumerable, ERC721Royalty, MintCounter, ReentrancyGuard, AccessControl, Ownable {
    bytes32 public constant SUPPORT_ROLE = keccak256('SUPPORT');
    uint256 public constant MAX_PUBLIC_MINT = 1;
    uint256 public constant MAX_RESERVE_SUPPLY = 0;
    uint256 public constant PRICE_PER_TOKEN = 0 ether;
    uint256 public constant MAX_SUPPLY = 10000;

    
    string public provenance;
    string private _baseURIextended;
    bool public saleActive;
    uint256 public reserveSupply;

    address payable public immutable shareholderAddress;

    constructor(address payable shareholderAddress_) ERC721("TestNft", "T") {
        require(shareholderAddress_ != address(0));

        // set immutable variables
        shareholderAddress = shareholderAddress_;

        // setup roles
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(SUPPORT_ROLE, msg.sender);
    }

    function _toString(uint256 value) internal pure virtual returns (string memory str) {
        assembly {
            // The maximum value of a uint256 contains 78 digits (1 byte per digit), but
            // we allocate 0xa0 bytes to keep the free memory pointer 32-byte word aligned.
            // We will need 1 word for the trailing zeros padding, 1 word for the length,
            // and 3 words for a maximum of 78 digits. Total: 5 * 0x20 = 0xa0.
            let m := add(mload(0x40), 0xa0)
            // Update the free memory pointer to allocate.
            mstore(0x40, m)
            // Assign the `str` to the end.
            str := sub(m, 0x20)
            // Zeroize the slot after the string.
            mstore(str, 0)

            // Cache the end of the memory to calculate the length later.
            let end := str

            // We write the string from rightmost digit to leftmost digit.
            // The following is essentially a do-while loop that also handles the zero case.
            // prettier-ignore
            for { let temp := value } 1 {} {
                str := sub(str, 1)
                // Write the character to the pointer.
                // The ASCII index of the '0' character is 48.
                mstore8(str, add(48, mod(temp, 10)))
                // Keep dividing `temp` until zero.
                temp := div(temp, 10)
                // prettier-ignore
                if iszero(temp) { break }
            }

            let length := sub(end, str)
            // Move the pointer 32 bytes leftwards to make room for the length.
            str := sub(str, 0x20)
            // Store the length.
            mstore(str, length)
        }

    }  

    /**
     * @dev prevents minting via another contract
     */
    modifier callerIsUser() {
        require(tx.origin == msg.sender, 'Must be the sender');
        _;
    }

    /**
     * @dev checks to see if amount of tokens to be minted would exceed the maximum supply allowed
     */
    modifier ableToMint(uint256 numberOfTokens) {
        require(totalSupply() + numberOfTokens <= MAX_SUPPLY, 'Purchase would exceed max tokens');
        _;
    }

    /**
     * @dev checks to see whether saleActive is true
     */
    modifier isPublicSaleActive() {
        require(saleActive, 'Public sale is not active');
        _;
    }

    ////////////////
    // admin
    ////////////////
    /**
     * @dev reserves a number of tokens
     */
    function devMint(uint256 numberOfTokens) external onlyRole(SUPPORT_ROLE) ableToMint(numberOfTokens) nonReentrant {
        require(reserveSupply + numberOfTokens <= MAX_RESERVE_SUPPLY, 'Number would exceed max reserve supply');
        uint256 ts = totalSupply();

        reserveSupply += numberOfTokens;
        for (uint256 index = 0; index < numberOfTokens; index++) {
            _safeMint(msg.sender, ts + index);
        }
    }

    /**
     * @dev allows public sale minting
     */
    function setSaleActive(bool state) external onlyRole(SUPPORT_ROLE) {
        saleActive = state;
    }

    ////////////////
    // tokens
    ////////////////
    /**
     * @dev sets the base uri for {_baseURI}
     */
    function setBaseURI(string memory baseURI_) external onlyRole(SUPPORT_ROLE) {
        _baseURIextended = baseURI_;
    }

    /**
     * @dev See {ERC721-_baseURI}.
     */
    function _baseURI() internal view virtual override returns (string memory) {
        return _baseURIextended;
    }

    /**
     * @dev sets the provenance hash
     */
    function setProvenance(string memory provenance_) external onlyRole(SUPPORT_ROLE) {
        provenance = provenance_;
    }

    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(AccessControl, ERC721Enumerable, ERC721Royalty)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    /**
     * @dev See {ERC721Enumerable-_beforeTokenTransfer}.
     */
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId
    ) internal override(ERC721, ERC721Enumerable) {
        super._beforeTokenTransfer(from, to, tokenId);
    }

    /**
     * @dev See {ERC721-_burn}.
     */
    function _burn(uint256 tokenId) internal override(ERC721, ERC721Royalty) {
        super._burn(tokenId);
    }

    ////////////////
    // public
    ////////////////
    /**
     * @dev allow public minting
     */
    function purchase(uint256 numberOfTokens)
        external
        payable
        isPublicSaleActive
        ableToMint(numberOfTokens)
        callerIsUser
        doesMintExceedMaximumPerAddress(numberOfTokens, MAX_PUBLIC_MINT)
        nonReentrant
    {
        require(numberOfTokens * PRICE_PER_TOKEN == msg.value, 'Ether value sent is not correct');
        uint256 ts = totalSupply();

        _incrementTokenMintCounter(numberOfTokens);
        for (uint256 index = 0; index < numberOfTokens; index++) {
            _safeMint(msg.sender, ts + index);
        }
    }

    ////////////////
    // royalty
    ////////////////
    /**
     * @dev See {ERC2981-_setDefaultRoyalty}.
     */
    function setDefaultRoyalty(address receiver, uint96 feeNumerator) external onlyRole(SUPPORT_ROLE) {
        _setDefaultRoyalty(receiver, feeNumerator);
    }

    /**
     * @dev See {ERC2981-_deleteDefaultRoyalty}.
     */
    function deleteDefaultRoyalty() external onlyRole(SUPPORT_ROLE) {
        _deleteDefaultRoyalty();
    }

    /**
     * @dev See {ERC2981-_setTokenRoyalty}.
     */
    function setTokenRoyalty(
        uint256 tokenId,
        address receiver,
        uint96 feeNumerator
    ) external onlyRole(SUPPORT_ROLE) {
        _setTokenRoyalty(tokenId, receiver, feeNumerator);
    }

    /**
     * @dev See {ERC2981-_resetTokenRoyalty}.
     */
    function resetTokenRoyalty(uint256 tokenId) external onlyRole(SUPPORT_ROLE) {
        _resetTokenRoyalty(tokenId);
    }

    /**
     * @dev Returns the Uniform Resource Identifier (URI) for `tokenId` token.
     */
    function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
        require(_exists(tokenId),"ERC721Metadata: URI query for nonexistent token");

        string memory baseURI = _baseURI();
        return bytes(baseURI).length != 0 ? string(abi.encodePacked(baseURI, _toString(tokenId))) : '';
    }

    ////////////////
    // withdraw
    ////////////////
    /**
     * @dev withdraws ether from the contract to the shareholder address
     */
    function withdraw() external onlyOwner nonReentrant {
        (bool success, ) = shareholderAddress.call{value: address(this).balance}('');
        require(success, 'Transfer failed.');
    }
    
}
