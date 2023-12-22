// SPDX-License-Identifier: MIT
pragma solidity 0.8.3;
import "./ERC721Upgradeable.sol";
import "./AccessControlEnumerableUpgradeable.sol";
import "./VerifySign.sol";

contract Item is
    ERC721Upgradeable,
    AccessControlEnumerableUpgradeable,
    VerifySign
{
    string private _uri;

    mapping(address => bool) public isMarketplace;
    bool public transferRestrictionFlag;

    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    // tokenId -> lock
    mapping(uint256 => bool) public locks;
    mapping(uint256 => uint256) public nonceMapping;

    event Deposit(uint256 indexed index, address sender);
    event Withdraw(uint256 indexed index, address sender);

    function initialize(
        string memory uri,
        address initOwner,
        address initMinter
    ) public initializer {
        __AccessControlEnumerable_init();
        __ERC721_init("MYTItem", "Mystic Treasure Item");
        _setURI(uri);
        _setupRole(DEFAULT_ADMIN_ROLE, initOwner);
        _setupRole(OPERATOR_ROLE, initOwner);
        _setupRole(MINTER_ROLE, initMinter);
    }

    function _setURI(string memory newuri) internal virtual {
        _uri = newuri;
    }

    function _baseURI() internal view virtual override returns (string memory) {
        return _uri;
    }

    function setURI(string memory newuri) external onlyRole(OPERATOR_ROLE) {
        _setURI(newuri);
    }

    function mintItem(
        address receiver,
        uint256 tokenId
    ) external onlyRole(MINTER_ROLE) {
        _mintItem(receiver, tokenId);
    }

    function msgHashMintItem(
        address receiver,
        uint256 tokenId
    ) public view returns (bytes32) {
        return keccak256(abi.encodePacked(receiver, address(this), tokenId));
    }

    function getSignerMint(
        address reveiver,
        uint256 tokenId,
        bytes memory signature
    ) public view returns (address) {
        bytes32 messageHash = msgHashMintItem(reveiver, tokenId);
        bytes32 ethSignedMessageHash = getEthSignedMessageHash(messageHash);
        return recoverSigner(ethSignedMessageHash, signature);
    }

    function claimMintItem(uint256 tokenId, bytes memory signature) external {
        // verify signature is signed by owner of item contract
        address receiver = _msgSender();
        address signer = getSignerMint(receiver, tokenId, signature);
        require(hasRole(MINTER_ROLE, signer), "Item: failure verify item");
        _mintItem(receiver, tokenId);
        emit Withdraw(tokenId, receiver);
    }

    function _mintItem(address receiver, uint256 newTokenId) internal {
        _mint(receiver, newTokenId);
    }

    /**
     * @dev Check if the item is tradeable or not.
     *
     * @param tokenId The id of the item to check against
     * @return A boolean of the status (true/false)
     */
    function isTradable(uint256 tokenId) public view returns (bool) {
        return !locks[tokenId];
    }

    function setTransferRestrictionFlag(
        bool flag
    ) public onlyRole(OPERATOR_ROLE) {
        transferRestrictionFlag = flag;
    }

    function setMarketplace(
        address marketplaceAddr,
        bool isActive
    ) public onlyRole(OPERATOR_ROLE) {
        isMarketplace[marketplaceAddr] = isActive;
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId
    ) internal virtual override {
        super._beforeTokenTransfer(from, to, tokenId);

        require(isTradable(tokenId), "Item: Token has been locked");

        if (transferRestrictionFlag == true) {
            require(
                from == address(0) || isMarketplace[_msgSender()],
                "Item: only allow mint transaction or trade on marketplace"
            );
        }
    }

    /**
     * @dev Lock item before using it in game
     */
    function deposit(uint256 tokenId) external {
        require(
            _isApprovedOrOwner(_msgSender(), tokenId),
            "ERC721: transfer caller is not owner nor approved"
        );
        require(
            locks[tokenId] == false,
            "Item: Token already deposited to game"
        );
        locks[tokenId] = true;
        emit Deposit(tokenId, _msgSender());
    }

    function itemExists(uint256 tokenId) public view returns (bool) {
        return _exists(tokenId);
    }

    function msgHashWithdrawItem(
        uint256 tokenId,
        uint256 nonce
    ) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(tokenId, nonce));
    }

    function getSignerWithdrawItem(
        uint256 tokenId,
        uint256 nonce,
        bytes memory signature
    ) public pure returns (address) {
        bytes32 messageHash = msgHashWithdrawItem(tokenId, nonce);
        bytes32 ethSignedMessageHash = getEthSignedMessageHash(messageHash);
        return recoverSigner(ethSignedMessageHash, signature);
    }

    /**
     * @dev Withdraw token
     */
    function withdraw(
        uint256 tokenId,
        uint256 nonce,
        bytes memory signature
    ) external {
        require(
            _isApprovedOrOwner(_msgSender(), tokenId),
            "ERC721: transfer caller is not owner nor approved"
        );
        require(locks[tokenId] == true, "Item: already unlock token");
        require(nonceMapping[tokenId] == nonce, "Item: Invalid nonce");
        address signer = getSignerWithdrawItem(tokenId, nonce, signature);
        require(hasRole(MINTER_ROLE, signer), "Item: failure verify signature");

        locks[tokenId] = false;
        nonceMapping[tokenId] = nonceMapping[tokenId] + 1;
        emit Withdraw(tokenId, _msgSender());
    }

    function supportsInterface(
        bytes4 interfaceId
    )
        public
        view
        virtual
        override(ERC721Upgradeable, AccessControlEnumerableUpgradeable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}

