// SPDX-License-Identifier: MIT
pragma solidity 0.8.6;

import "./Counters.sol";
import "./Context.sol";
import "./Ownable.sol";
import "./AccessControlEnumerable.sol";

import "./ERC721Enumerable.sol";
import "./ERC721Burnable.sol";
import "./ERC721Pausable.sol";
import "./ERC721URIStorage.sol";
import "./ERC721Royalty.sol";
import "./IERC20.sol";

import "./Withdrawable.sol";
import "./ERC721Freezable.sol";
import "./IChildToken.sol";
import "./NativeMetaTransaction.sol";
import "./IMintableERC721.sol";

contract District is
    IChildToken,
    Ownable,
    AccessControlEnumerable,
    ERC721Enumerable,
    ERC721Burnable,
    ERC721Pausable,
    ERC721URIStorage,
    ERC721Royalty,
    Withdrawable,
    ERC721Freezable,
    NativeMetaTransaction,
    IMintableERC721
{
    using Counters for Counters.Counter;
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant TRANSFER_ROLE = keccak256("TRANSFER_ROLE");
    bytes32 public constant DEPOSITOR_ROLE = keccak256("DEPOSITOR_ROLE");
    bytes32 public constant PREDICATE_ROLE = keccak256("PREDICATE_ROLE");

    Counters.Counter private _tokenIdTracker;
    string public _baseTokenURI;
    bool public useTransferRole = false;

    mapping(uint256 => bool) public withdrawnTokens;

    // limit batching of tokens due to gas limit restrictions
    uint256 public constant BATCH_LIMIT = 20;

    event WithdrawnBatch(address indexed user, uint256[] tokenIds);
    event TransferWithMetadata(address indexed from, address indexed to, uint256 indexed tokenId, bytes metaData);

    constructor(
        string memory name,
        string memory symbol,
        string memory baseTokenURI
    ) ERC721(name, symbol) {
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());

        _setupRole(MINTER_ROLE, _msgSender());
        _setupRole(WITHDRAWER_ROLE, _msgSender());
        _setupRole(PAUSER_ROLE, _msgSender());
        _setupRole(TRANSFER_ROLE, _msgSender());
        _setupRole(DEPOSITOR_ROLE, address(0xA6FA4fB5f76172d178d61B04b0ecd319C5d1C0aa));
        _setupRole(PREDICATE_ROLE, address(0x932532aA4c0174b8453839A6E44eE09Cc615F2b7));
        _baseTokenURI = baseTokenURI;
        mint(_msgSender());
        freezeToken(0, true);
        _initializeEIP712(name);
    }

    function msgSender() internal view returns (address payable sender) {
        if (msg.sender == address(this)) {
            bytes memory array = msg.data;
            uint256 index = msg.data.length;
            assembly {
                // Load the 32 bytes word from memory with the address on the lower 20 bytes, and mask those.
                sender := and(mload(add(array, index)), 0xffffffffffffffffffffffffffffffffffffffff)
            }
        } else {
            sender = payable(msg.sender);
        }
        return sender;
    }

    function _msgSender() internal view override returns (address) {
        return msgSender();
    }

    function setActivateTransferRole(bool flag) public {
        require(hasRole(DEFAULT_ADMIN_ROLE, _msgSender()), "setActivateTransferRole: must have admin role");
        useTransferRole = flag;
    }

    function _baseURI() internal view virtual override returns (string memory) {
        return _baseTokenURI;
    }

    function setBaseURI(string memory baseTokenURI) public {
        require(hasRole(MINTER_ROLE, _msgSender()), "setBaseURI: must have minter role");
        _baseTokenURI = baseTokenURI;
    }

    function setTokenURI(uint256 tokenId, string memory uri) public {
        require(hasRole(MINTER_ROLE, _msgSender()), "setTokenURI: must have minter role");
        _setTokenURI(tokenId, uri);
    }

    function tokenURI(uint256 tokenId) public view virtual override(ERC721, ERC721URIStorage) returns (string memory) {
        return super.tokenURI(tokenId);
    }

    function mint(address to) public returns (uint256 tokenId) {
        require(hasRole(MINTER_ROLE, _msgSender()), "mint: must have minter role to mint");

        tokenId = _tokenIdTracker.current();
        require(!withdrawnTokens[tokenId], "ChildMintableERC721: TOKEN_EXISTS_ON_ROOT_CHAIN");
        _mint(to, tokenId);
        _tokenIdTracker.increment();
    }

    function pause() public virtual {
        require(hasRole(PAUSER_ROLE, _msgSender()), "pause: must have pauser role to pause");
        _pause();
    }

    function unpause() public virtual {
        require(hasRole(PAUSER_ROLE, _msgSender()), "unpause: must have pauser role to unpause");
        _unpause();
    }

    function _burn(uint256 tokenId) internal virtual override(ERC721, ERC721URIStorage, ERC721Royalty) {
        super._burn(tokenId);
    }

    function freezeAccount(address account, bool flag) public {
        require(hasRole(PAUSER_ROLE, _msgSender()), "freeze: must have pauser role to freeze");
        _freezeAccount(account, flag);
    }

    function freezeToken(uint256 tokenId, bool flag) public {
        require(hasRole(PAUSER_ROLE, _msgSender()), "freeze: must have pauser role to freeze");
        _freezeToken(tokenId, flag);
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId
    ) internal virtual override(ERC721, ERC721Pausable, ERC721Enumerable, ERC721Freezable) {
        require(
            paused() == false || hasRole(PAUSER_ROLE, _msgSender()) == true,
            "ERC721Pausable: token transfer while paused"
        );

        require(
            useTransferRole == false || ownerOf(tokenId) == _msgSender() || hasRole(TRANSFER_ROLE, _msgSender()),
            "transfer: owner or need transfer role"
        );

        super._beforeTokenTransfer(from, to, tokenId);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(ERC721, AccessControlEnumerable, ERC721Enumerable, ERC721Royalty, IERC165)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    function approve(address to, uint256 tokenId) public virtual override(ERC721, ERC721Freezable, IERC721) {
        super.approve(to, tokenId);
    }

    function tokensOfOwner(address owner) public view returns (uint256[] memory result) {
        uint256 count = balanceOf(owner);
        result = new uint256[](count);
        for (uint256 i = 0; i < count; i++) {
            result[i] = tokenOfOwnerByIndex(owner, i);
        }

        return result;
    }

    /**
     * @notice called when token is deposited on root chain
     * @dev Should be callable only by ChildChainManager
     * Should handle deposit by minting the required tokenId(s) for user
     * Should set `withdrawnTokens` mapping to `false` for the tokenId being deposited
     * Minting can also be done by other functions
     * @param user user address for whom deposit is being done
     * @param depositData abi encoded tokenIds. Batch deposit also supported.
     */
    function deposit(address user, bytes calldata depositData) external override {
        require(hasRole(DEPOSITOR_ROLE, _msgSender()), "mint: must have minter role to mint");

        // deposit single
        if (depositData.length == 32) {
            uint256 tokenId = abi.decode(depositData, (uint256));
            withdrawnTokens[tokenId] = false;
            _mint(user, tokenId);

            // deposit batch
        } else {
            uint256[] memory tokenIds = abi.decode(depositData, (uint256[]));
            uint256 length = tokenIds.length;
            for (uint256 i; i < length; i++) {
                withdrawnTokens[tokenIds[i]] = false;
                _mint(user, tokenIds[i]);
            }
        }
    }

    /**
     * @notice called when user wants to withdraw token back to root chain
     * @dev Should handle withraw by burning user's token.
     * Should set `withdrawnTokens` mapping to `true` for the tokenId being withdrawn
     * This transaction will be verified when exiting on root chain
     * @param tokenId tokenId to withdraw
     */
    function withdraw(uint256 tokenId) external {
        require(_msgSender() == ownerOf(tokenId), "ChildMintableERC721: INVALID_TOKEN_OWNER");
        withdrawnTokens[tokenId] = true;
        _burn(tokenId);
    }

    /**
     * @notice called when user wants to withdraw multiple tokens back to root chain
     * @dev Should burn user's tokens. This transaction will be verified when exiting on root chain
     * @param tokenIds tokenId list to withdraw
     */
    function withdrawBatch(uint256[] calldata tokenIds) external {
        uint256 length = tokenIds.length;
        require(length <= BATCH_LIMIT, "ChildMintableERC721: EXCEEDS_BATCH_LIMIT");

        // Iteratively burn ERC721 tokens, for performing
        // batch withdraw
        for (uint256 i; i < length; i++) {
            uint256 tokenId = tokenIds[i];

            require(
                _msgSender() == ownerOf(tokenId),
                string(abi.encodePacked("ChildMintableERC721: INVALID_TOKEN_OWNER ", tokenId))
            );
            withdrawnTokens[tokenId] = true;
            _burn(tokenId);
        }

        // At last emit this event, which will be used
        // in MintableERC721 predicate contract on L1
        // while verifying burn proof
        emit WithdrawnBatch(_msgSender(), tokenIds);
    }

    /**
     * @notice called when user wants to withdraw token back to root chain with token URI
     * @dev Should handle withraw by burning user's token.
     * Should set `withdrawnTokens` mapping to `true` for the tokenId being withdrawn
     * This transaction will be verified when exiting on root chain
     *
     * @param tokenId tokenId to withdraw
     */
    function withdrawWithMetadata(uint256 tokenId) external {
        require(_msgSender() == ownerOf(tokenId), "ChildMintableERC721: INVALID_TOKEN_OWNER");
        withdrawnTokens[tokenId] = true;

        // Encoding metadata associated with tokenId & emitting event
        emit TransferWithMetadata(ownerOf(tokenId), address(0), tokenId, this.encodeTokenMetadata(tokenId));

        _burn(tokenId);
    }

    /**
     * @notice This method is supposed to be called by client when withdrawing token with metadata
     * and pass return value of this function as second paramter of `withdrawWithMetadata` method
     *
     * It can be overridden by clients to encode data in a different form, which needs to
     * be decoded back by them correctly during exiting
     *
     * @param tokenId Token for which URI to be fetched
     */
    function encodeTokenMetadata(uint256 tokenId) external view virtual returns (bytes memory) {
        // You're always free to change this default implementation
        // and pack more data in byte array which can be decoded back
        // in L1
        return abi.encode(tokenURI(tokenId));
    }

    /**
     * @dev See {IMintableERC721-mint}.
     */
    function mint(address user, uint256 tokenId) external override {
        require(hasRole(PREDICATE_ROLE, _msgSender()), "mint: must have minter role to mint");
        _mint(user, tokenId);
    }

    /**
     * If you're attempting to bring metadata associated with token
     * from L2 to L1, you must implement this method, to be invoked
     * when minting token back on L1, during exit
     */
    function setTokenMetadata(uint256 tokenId, bytes memory data) internal virtual {
        // This function should decode metadata obtained from L2
        // and attempt to set it for this `tokenId`
        //
        // Following is just a default implementation, feel
        // free to define your own encoding/ decoding scheme
        // for L2 -> L1 token metadata transfer
        string memory uri = abi.decode(data, (string));

        _setTokenURI(tokenId, uri);
    }

    /**
     * @dev See {IMintableERC721-mint}.
     *
     * If you're attempting to bring metadata associated with token
     * from L2 to L1, you must implement this method
     */
    function mint(
        address user,
        uint256 tokenId,
        bytes calldata metaData
    ) external override {
        require(hasRole(PREDICATE_ROLE, _msgSender()), "mint: must have minter role to mint");
        _mint(user, tokenId);
        setTokenMetadata(tokenId, metaData);
    }

    /**
     * @dev See {IMintableERC721-exists}.
     */

    function exists(uint256 tokenId) external view override returns (bool) {
        return _exists(tokenId);
    }
}

