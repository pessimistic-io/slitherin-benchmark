// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.17;

import "./OwnableUpgradeable.sol";
import "./SafeMathUpgradeable.sol";
import "./AddressUpgradeable.sol";
import "./ERC721HolderUpgradeable.sol";
import "./ERC1155HolderUpgradeable.sol";
import "./SafeERC20Upgradeable.sol";
import "./ECDSAUpgradeable.sol";
import "./IERC20Upgradeable.sol";

import "./IBattlefly.sol";
import "./ISpecialNFT.sol";
import "./IItem.sol";

contract BattleflyGameV2 is OwnableUpgradeable, ERC1155HolderUpgradeable, ERC721HolderUpgradeable {
    using SafeMathUpgradeable for uint256;
    using AddressUpgradeable for address;
    using SafeERC20Upgradeable for IERC20Upgradeable;

    mapping(address => bool) private adminAccess;
    IBattlefly private BattleflyContract;
    ISpecialNFT private SpecialNFTContract;
    IERC20Upgradeable private MagicToken;
    IItem private ItemContract;

    mapping(uint256 => bool) public ProcessedTransactions;
    uint8 constant TRANSACTION_TYPE_WITHDRAW_BATTLEFLY = 0;
    uint8 constant TRANSACTION_TYPE_WITHDRAW_MAGIC = 1;
    uint8 constant TRANSACTION_TYPE_WITHDRAW_ITEM = 2;

    event DepositBattlefly(uint256 indexed tokenId, address indexed user, uint256 timestamp);
    event WithdrawBattlefly(uint256 indexed tokenId, address indexed receiver, uint256 timestamp);

    event DepositItems(uint256 indexed tokenId, address indexed user, uint256 amount, uint256 timestamp);
    event WithdrawItems(uint256 indexed tokenId, address indexed receiver, uint256 amount, uint256 timestamp);

    event DepositMagic(uint256 amount, address indexed user, uint256 timestamp);
    event WithdrawMagic(uint256 amount, address indexed receiver, uint256 timestamp, uint256 walletTransactionId);

    event MintBattlefly(address indexed receiver, uint256 tokenId, uint256 battleflyType);
    event MintBattleflies(address[] receivers, uint256[] tokenIds, uint256[] battleflyTypes);

    event MintSpecialNFT(address indexed receiver, uint256 tokenId, uint256 specialNFTType);
    event MintSpecialNFTs(address[] receivers, uint256[] tokenIds, uint256[] specialNFTTypes);

    event SetAdminAccess(address indexed user, bool access);
    event MintItems(uint256 indexed itemId, address indexed receiver, uint256 amount);

    function initialize(
        address battleflyContractAddress,
        address specialNFTContractAddress,
        address magicTokenAddress
    ) public initializer {
        __Ownable_init();
        BattleflyContract = IBattlefly(battleflyContractAddress);
        SpecialNFTContract = ISpecialNFT(specialNFTContractAddress);
        MagicToken = IERC20Upgradeable(magicTokenAddress);
    }

    function initializeUpgrade(address itemContractAddress) external onlyOwner {
        ItemContract = IItem(itemContractAddress);
    }

    function setMagic(address magicAddress) external onlyOwner {
        MagicToken = IERC20Upgradeable(magicAddress);
    }

    function getBattlefliesOfOwner(address user) external view returns (uint256[] memory) {
        uint256 balance = BattleflyContract.balanceOf(user);
        uint256[] memory tokenIds = new uint256[](balance);
        for (uint256 i = 0; i < balance; i++) {
            tokenIds[i] = BattleflyContract.tokenOfOwnerByIndex(user, i);
        }
        return tokenIds;
    }

    function getSpecialNFTsOfOwner(address user) external view returns (uint256[] memory) {
        uint256 balance = SpecialNFTContract.balanceOf(user);
        uint256[] memory tokenIds = new uint256[](balance);
        for (uint256 i = 0; i < balance; i++) {
            tokenIds[i] = SpecialNFTContract.tokenOfOwnerByIndex(user, i);
        }
        return tokenIds;
    }

    // ADMIN
    function setAdminAccess(address user, bool access) external onlyOwner {
        adminAccess[user] = access;
        emit SetAdminAccess(user, access);
    }

    function mintSpecialNFT(address receiver, uint256 specialNFTType) external onlyAdminAccess returns (uint256) {
        uint256 tokenId = SpecialNFTContract.mintSpecialNFT(receiver, specialNFTType);
        emit MintSpecialNFT(receiver, tokenId, specialNFTType);
        return tokenId;
    }

    function mintSpecialNFTs(
        address receiver,
        uint256 specialNFTType,
        uint256 amount
    ) external onlyAdminAccess returns (uint256[] memory) {
        uint256[] memory tokenIds = SpecialNFTContract.mintSpecialNFTs(receiver, specialNFTType, amount);
        for (uint256 i = 0; i < amount; i++) {
            emit MintSpecialNFT(receiver, tokenIds[i], specialNFTType);
        }
        return tokenIds;
    }

    function mintItems(
        uint256 itemId,
        address receiver,
        uint256 amount
    ) external onlyAdminAccess {
        ItemContract.mintItems(itemId, receiver, amount, "");
        emit MintItems(itemId, receiver, amount);
    }

    function mintBattlefly(address receiver, uint256 battleflyType) external onlyAdminAccess returns (uint256) {
        uint256 tokenId = BattleflyContract.mintBattlefly(receiver, battleflyType);
        emit MintBattlefly(receiver, tokenId, battleflyType);
        return tokenId;
    }

    function mintBattleflies(
        address receiver,
        uint256 battleflyType,
        uint256 amount
    ) external onlyAdminAccess returns (uint256[] memory) {
        uint256[] memory tokenIds = BattleflyContract.mintBattleflies(receiver, battleflyType, amount);
        for (uint256 i = 0; i < amount; i++) {
            emit MintBattlefly(receiver, tokenIds[i], battleflyType);
        }
        return tokenIds;
    }

    // Battlefly
    function bulkDepositBattlefly(uint256[] memory tokenIds) external {
        for (uint256 i = 0; i < tokenIds.length; i++) {
            depositBattlefly(tokenIds[i]);
        }
    }

    function depositBattlefly(uint256 tokenId) public {
        BattleflyContract.safeTransferFrom(_msgSender(), address(this), tokenId);
        emit DepositBattlefly(tokenId, _msgSender(), block.timestamp);
    }

    function withdrawBattlefly(uint256 tokenId, address receiver) external onlyAdminAccess {
        BattleflyContract.safeTransferFrom(address(this), receiver, tokenId);
        emit WithdrawBattlefly(tokenId, receiver, block.timestamp);
    }

    function claimWithdrawBattleflies(
        uint256[] memory tokenIds,
        uint256 transactionId,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        require(ProcessedTransactions[transactionId] == false, "Transaction have been processed");
        ProcessedTransactions[transactionId] = true;
        bytes32 payloadHash = keccak256(
            abi.encodePacked(_msgSender(), tokenIds, transactionId, TRANSACTION_TYPE_WITHDRAW_BATTLEFLY)
        );
        bytes32 messageHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", payloadHash));
        (address admin, ECDSAUpgradeable.RecoverError result) = ECDSAUpgradeable.tryRecover(messageHash, v, r, s);
        require(result == ECDSAUpgradeable.RecoverError.NoError && adminAccess[admin], "Require admin access");
        for (uint256 i = 0; i < tokenIds.length; i++) {
            BattleflyContract.safeTransferFrom(address(this), _msgSender(), tokenIds[i]);
            emit WithdrawBattlefly(tokenIds[i], _msgSender(), block.timestamp);
        }
    }

    //Magic token
    function depositMagic(uint256 amount) external {
        MagicToken.safeTransferFrom(_msgSender(), address(this), amount);
        emit DepositMagic(amount, _msgSender(), block.timestamp);
    }

    function claimWithdrawMagic(
        uint256 amount,
        uint256 transactionId,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        require(ProcessedTransactions[transactionId] == false, "Transaction have been processed");
        ProcessedTransactions[transactionId] = true;
        bytes32 payloadHash = keccak256(
            abi.encodePacked(_msgSender(), amount, transactionId, TRANSACTION_TYPE_WITHDRAW_MAGIC)
        );
        bytes32 messageHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", payloadHash));
        (address admin, ECDSAUpgradeable.RecoverError result) = ECDSAUpgradeable.tryRecover(messageHash, v, r, s);
        require(result == ECDSAUpgradeable.RecoverError.NoError && adminAccess[admin], "Require admin access");
        MagicToken.safeTransfer(_msgSender(), amount);
        emit WithdrawMagic(amount, _msgSender(), block.timestamp, transactionId);
    }

    //Item
    function depositItems(uint256 itemId, uint256 amount) external {
        ItemContract.safeTransferFrom(_msgSender(), address(this), itemId, amount, "");
        emit DepositItems(itemId, _msgSender(), amount, block.timestamp);
    }

    function withdrawItems(
        uint256 itemId,
        uint256 amount,
        address receiver
    ) external onlyAdminAccess {
        ItemContract.safeTransferFrom(address(this), receiver, itemId, amount, "");
        emit WithdrawItems(itemId, receiver, amount, block.timestamp);
    }

    function claimWithdrawItems(
        uint256 itemId,
        uint256 amount,
        uint256 transactionId,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        require(ProcessedTransactions[transactionId] == false, "Transaction have been processed");
        ProcessedTransactions[transactionId] = true;
        bytes32 payloadHash = keccak256(
            abi.encodePacked(_msgSender(), itemId, amount, transactionId, TRANSACTION_TYPE_WITHDRAW_ITEM)
        );
        bytes32 messageHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", payloadHash));
        (address admin, ECDSAUpgradeable.RecoverError result) = ECDSAUpgradeable.tryRecover(messageHash, v, r, s);
        require(result == ECDSAUpgradeable.RecoverError.NoError && adminAccess[admin], "Require admin access");
        ItemContract.safeTransferFrom(address(this), _msgSender(), itemId, amount, "");
        emit WithdrawItems(itemId, _msgSender(), amount, block.timestamp);
    }

    //modifier
    modifier onlyAdminAccess() {
        require(adminAccess[_msgSender()] == true || _msgSender() == owner(), "Require admin access");
        _;
    }
}

