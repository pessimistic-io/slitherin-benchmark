/*
Crafted with love by
Fueled on Bacon
https://fueledonbacon.com
*/
//SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "./MerkleProof.sol";
import "./Ownable.sol";
import "./IERC20.sol";

import "./ERC721A.sol";

contract MagicNFT is ERC721A, Ownable {
    using Strings for uint256;

    address private _revenueRecipient;
    address private immutable _magicToken;
    
    bytes32 private _whitelistMerkleRoot;
    bytes32 private _reserveListMerkleRoot;

    mapping(address=>uint256) private _mintedWLTokensByUser;
    mapping(address=>uint256) private _mintedRTokensByUser;

    string private _baseUri;
    string private _tempUri;
    
    bool private _revealed;
    bool private _overrideWhitelist;
    bool private _overrideReservelist;
    bool private _overridePublicSale;

    uint256 public constant AIRDROP_LIMIT   = 444;
    uint256 public constant COLLECTION_SIZE = 6444;
    uint256 public constant PUBLIC_LIMIT = 10;
    uint256 public constant ETHER_PRICE = 0.025 ether;
    uint256 public constant MAGIC_PRICE = 140 ether;

    uint256 public immutable whitelistStart;
    uint256 public immutable whitelistEnd;
    uint256 public immutable reserveListStart;
    uint256 public immutable reserveListEnd;
    uint256 public immutable publicSaleStart;
    uint256 public airdropped;

    constructor(
        address magicToken,
        address revenueRecipient,
        uint256 _whitelistStart,
        uint256 _whitelistEnd,
        uint256 _reserveListStart,
        uint256 _reserveListEnd,
        uint256 _publicSaleStart,
        string memory tempUri
    )
        ERC721A("Magic potions - Alchemists", "MPALC")
    {
        require(_whitelistStart > block.timestamp, "WRONG_WL_START");
        require(_whitelistEnd > _whitelistStart, "WRONG_WL_END");

        require(_reserveListStart > block.timestamp, "WRONG_RV_START");
        require(_reserveListEnd > _reserveListStart, "WRONG_RV_END");

        require(_publicSaleStart > block.timestamp, "WRONG_PS_START");

        _magicToken = magicToken;
        _revenueRecipient  = revenueRecipient;

        whitelistStart = _whitelistStart;
        whitelistEnd = _whitelistEnd;

        reserveListStart = _reserveListStart;
        reserveListEnd = _reserveListEnd;

        publicSaleStart = _publicSaleStart;
        _tempUri = tempUri;
    }
    
    /// @notice the initial 100 tokens will be minted to the team vault for use in giveaways and collaborations.
    function airdrop(address to, uint256 quantity) external onlyOwner {
        require(totalSupply() + quantity <= COLLECTION_SIZE, "EXCEEDS_COLLECTION_SIZE");
        airdropped += quantity;
        require(airdropped <= AIRDROP_LIMIT, "EXCEEDS_AIRDROP_LIMIT");
        _safeMint(to, quantity);
    }

    function isWhitelistSaleActive() public view returns(bool){
        require(_whitelistMerkleRoot != "", "EMPTY_MERKLEROOT");
        if(_overrideWhitelist){
            return true;
        }
        return block.timestamp > whitelistStart && block.timestamp < whitelistEnd;
    }

    function isReserveListSaleActive() public view returns(bool){
        require(_reserveListMerkleRoot != "", "EMPTY_MERKLEROOT");
        if(_overrideReservelist){
            return true;
        }
        return block.timestamp > reserveListStart && block.timestamp < reserveListEnd;
    }

    function isPublicSaleActive() public view returns(bool){
        if(_overridePublicSale){
            return true;
        }
        return block.timestamp > publicSaleStart;
    }

    function toggleReveal() external onlyOwner {
        _revealed = !_revealed;
    }

    function toggleWhitelistSale() external onlyOwner {
        _overrideWhitelist = !_overrideWhitelist;
    }

    function toggleReserveSale() external onlyOwner {
        _overrideReservelist = !_overrideReservelist;
    }

    function togglePublicSale() external onlyOwner {
        _overridePublicSale = !_overridePublicSale;
    }

    function setBaseURI(string memory baseUri) external onlyOwner {
        _baseUri = baseUri;
    }

    function setPlaceholderURI(string memory tempUri) external onlyOwner {
        _tempUri = tempUri;
    }

    function setWhitelistMerkleRoot(bytes32 merkleRoot) external onlyOwner {
        _whitelistMerkleRoot = merkleRoot;
    }

    function setReservelistMerkleRoot(bytes32 merkleRoot) external onlyOwner {
        _reserveListMerkleRoot = merkleRoot;
    }

    function setRevenueRecipient(address recipient) external onlyOwner {
        require(recipient != address(0), "RECIPIENT_ZERO_ADDRESSS");
        _revenueRecipient = recipient;
    }

    /// @dev override base uri. It will be combined with token ID
    function _baseURI() internal view override returns (string memory) {
        return _baseUri;
    }

    /// @notice Withdraw's contract's balance to the withdrawal address
    function withdrawETH() external {
        uint256 balance = address(this).balance;
        require(balance > 0, "NO_BALANCE");
        (bool success, ) = payable(_revenueRecipient).call{ value: balance }("");
        require(success, "WITHDRAW_FAILED");
    }

    function withdraw(address token) external {
        IERC20 _token = IERC20(token);
        _token.transfer(_revenueRecipient, _token.balanceOf(address(this)));
    }

    function verifyWhitelist(bytes32[] calldata _merkleProof, address addr, uint256 quantity) public view returns(bool) {
        return (MerkleProof.verify(_merkleProof, _whitelistMerkleRoot, keccak256(abi.encode(addr, quantity))) == true);
    }

    function verifyReservelist(bytes32[] calldata _merkleProof, address addr, uint256 quantity) public view returns(bool) {
        return (MerkleProof.verify(_merkleProof, _reserveListMerkleRoot, keccak256(abi.encode(addr, quantity))) == true);
    }
    
    /// @param _merkleProof merkleproof
    /// @param maxToMint merkleproof value
    /// @param quantity less or equal maxToMint
    function whitelistMint(bytes32[] calldata _merkleProof, uint256 maxToMint, uint256 quantity) external payable {
        address account = _msgSender();
        require(_mintedWLTokensByUser[account] + quantity <= maxToMint, "EXCEEDS_MAXIMUM");
        require(isWhitelistSaleActive(), "PRESALE_INACTIVE");
        require(verifyWhitelist(_merkleProof, account, maxToMint), "PRESALE_NOT_VERIFIED");
        require(totalSupply() + quantity <= COLLECTION_SIZE, "EXCEEDS_COLLECTION_SIZE");
        uint256 cost = quantity * ETHER_PRICE;
        require(msg.value >= cost, "VALUE_TOO_LOW");
        _mintedWLTokensByUser[account] += quantity;
        _safeMint(account, quantity);
    }

    function reserveListMint(bytes32[] calldata _merkleProof, uint256 maxToMint, uint256 quantity) external payable {
        address account = _msgSender();
        require(_mintedRTokensByUser[account] + quantity <= maxToMint, "EXCEEDS_MAXIMUM");
        require(isReserveListSaleActive(), "PRESALE_INACTIVE");
        require(verifyReservelist(_merkleProof, account, maxToMint), "PRESALE_NOT_VERIFIED");
        require(totalSupply() + quantity <= COLLECTION_SIZE, "EXCEEDS_COLLECTION_SIZE");
        uint256 cost = quantity * ETHER_PRICE;
        require(msg.value >= cost, "VALUE_TOO_LOW");
        _mintedRTokensByUser[account] += quantity;
        _safeMint(account, quantity);
    }


    function mint(uint256 quantity) external payable {
        require(quantity <= PUBLIC_LIMIT, "CANT_MINT_MORE_THAN_10");
        require(isPublicSaleActive(), "PUBLIC_SALE_NOT_ACTIVE");
        require(totalSupply() + quantity <= COLLECTION_SIZE, "EXCEEDS_COLLECTION_SIZE");
        address account = _msgSender();
        uint256 value = msg.value;
        if(value > 0) {
            uint256 cost = quantity * ETHER_PRICE;
            require(value >= cost, "VALUE_TOO_LOW");
        } else {
            uint256 cost = quantity * MAGIC_PRICE;
            IERC20(_magicToken).transferFrom(account, address(this), cost);
        }
        _safeMint(account, quantity);
    }


    function tokenURI(uint256 id) public view override returns (string memory) {
        require(_exists(id), "INVALID_ID");

        return _revealed
            ? string(abi.encodePacked(_baseURI(), id.toString(), ".json"))
            : _tempUri;
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC721A) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

}
