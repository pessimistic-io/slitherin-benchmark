// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./extensions_IERC721EnumerableUpgradeable.sol";
import "./IBattlefly.sol";
import "./IBattleflyGame.sol";

interface ISoulboundBattlefly is IERC721EnumerableUpgradeable {
    event Minted(
        address indexed receiver,
        uint256 indexed tokenId,
        uint256 battleflyType,
        uint256 transactionId,
        bytes signature,
        bool stake
    );
    event MintedWhitelist(
        address indexed receiver,
        uint256 indexed tokenId,
        uint256 battleflyType,
        bytes32 merkleroot,
        uint256 index,
        bool stake
    );
    event MerklerootForTypeSet(uint256 battleflyType, bytes32 merkleRoot);
    event TypeAdded(uint256 battleflyType);
    event TypeStatusSet(uint256 battleflyType, bool status);
    event ReceiverAddressWhitelisted(address account, bool status);
    event Paused(bool status);

    error UnexistingToken(uint256 tokenId);
    error InvalidBattleflyType(uint256 battleflyType);
    error TypeNotActive(uint256 battleflyType);
    error AlreadyMinted(bytes signature);
    error InvalidSignature(bytes signature);
    error AlreadyMintedWhitelist(uint256 index, bytes32 merkleroot);
    error AlreadyMintedFullAllocationForWhitelist(address account, uint256 battleflyType);
    error InvalidProof();
    error TransferNotAllowed(address from, address to, uint256 firstTokenId);
    error AccessDenied();
    error InvalidAddress(address account);
    error ContractPaused();

    function mint(bool stake, bytes calldata data) external;

    function mintWhitelist(
        uint256 index,
        address account,
        uint256 amount,
        uint256 battleflyType,
        bool stake,
        bytes32[] calldata merkleProof
    ) external;

    function setMerklerootForType(uint256 battleflyType, bytes32 merkleRoot) external;

    function addType() external;

    function setTypeStatus(uint256 battleflyType, bool status) external;

    function setPaused(bool status) external;

    function whitelistReceiverAddress(address account, bool status) external;

    function isWhitelistedReceiverAddress(address account) external view returns (bool);

    function getMerklerootForType(uint256 battleflyType) external view returns (bytes32);

    function isActiveType(uint256 battleflyType) external view returns (bool);

    function totalMintedForTypeByAddress(address account, uint256 battleflyType) external view returns (uint256);

    function game() external view returns (IBattleflyGame game);

    function currentId() external view returns (uint256);

    function battleflyTypeCounter() external view returns (uint256);
}

