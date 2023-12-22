// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./ERC721Enumerable.sol";
import "./ReentrancyGuard.sol";
import "./AccessControl.sol";
import "./Ownable.sol";
import "./ERC721Royalty.sol";
import "./MerkleProof.sol";
import "./MintCounter.sol";

contract XmultiverseCosmicOdysseyTicket  is ERC721Enumerable, ERC721Royalty, MintCounter, ReentrancyGuard, AccessControl, Ownable {
    bytes32 public constant SUPPORT_ROLE = keccak256('SUPPORT');
    uint256 public constant MAX_PUBLIC_MINT = 1;
    uint256 public constant MAX_RESERVE_SUPPLY = 0;
    uint256 public constant MAX_SUPPLY = 2000;


    bytes32 public merkleRoot;
    string public provenance;
    string private _baseURIextended;
    bool public saleActive;
    uint256 public reserveSupply;

    address payable public immutable shareholderAddress;
    mapping(address => bool) public airDropClaimed;

    constructor(address payable shareholderAddress_) ERC721("Xmultiverse Cosmic Odyssey Ticket", "XMOT") {
        require(shareholderAddress_ != address(0));

        // set immutable variables
        shareholderAddress = shareholderAddress_;

        // setup roles
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(SUPPORT_ROLE, msg.sender);
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

    function setMerkleRoot(bytes32 merkleRoot_) external onlyRole(SUPPORT_ROLE) {
        merkleRoot = merkleRoot_;
    }


    ////////////////
    // tokens
    ////////////////

    /**
     * @dev sets the isEligibleForAirDrop for {address,proof}
     */
    function isEligibleForAirDrop(
        address userAddress,
        bytes32[] calldata merkleProof
    ) external view returns (bool) {
        bytes32 node = keccak256(abi.encodePacked(userAddress));
        return MerkleProof.verify(merkleProof, merkleRoot, node);
    }

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
    function airdrop(
        uint256 numberOfTokens,
        bytes32[] calldata merkleProof
    )
        external
        isPublicSaleActive
        ableToMint(numberOfTokens)
        callerIsUser
        doesMintExceedMaximumPerAddress(numberOfTokens, MAX_PUBLIC_MINT)
        nonReentrant
    {
        // 验证MerkleProof
        bytes32 node = keccak256(abi.encodePacked(msg.sender));
        require(
            MerkleProof.verify(merkleProof, merkleRoot, node),
            "Invalid Merkle proof"
        );

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

    function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
        _requireMinted(tokenId);

        string memory baseURI = _baseURI();
        return bytes(baseURI).length > 0 ? string(baseURI) : "";
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
