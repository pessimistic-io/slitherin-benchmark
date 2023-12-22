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
import "./IWastelands.sol";

contract BattleflyGameV2 is OwnableUpgradeable, ERC1155HolderUpgradeable, ERC721HolderUpgradeable {
    using SafeMathUpgradeable for uint256;
    using AddressUpgradeable for address;
    using SafeERC20Upgradeable for IERC20Upgradeable;

    event DepositMagic(uint256 amount, address indexed user, uint256 timestamp);
    event WithdrawMagic(uint256 amount, address indexed receiver, uint256 timestamp, uint256 walletTransactionId);
    event SetAdminAccess(address indexed user, bool access);
    event WastelandsRewardsToppedUp(address indexed user, uint256 amount, uint256 timestamp);
    event Paused();
    event Unpaused();
    event PauseGuardianAdded(address indexed user);
    event PauseGuardianRemoved(address indexed user);
    event PendingWithdrawalCreated(uint256 amount, address indexed user, uint256 walletTransactionId, uint256 pendingId, uint256 timestamp);
    event PendingWithdrawalProcessed(address sender, address indexed user, uint256 amount, uint256 indexed transactionId, uint256 indexed pendingId, bool authorize, uint256 timestamp);
    event LeaderboardRewardsToppedUp(uint256 amount, address indexed sender, uint256 timestamp);

    mapping(address => bool) private adminAccess;
    IBattlefly public BattleflyContract;
    ISpecialNFT public SpecialNFTContract;
    IERC20Upgradeable public MagicToken;
    IItem public ItemContract;

    mapping(uint256 => bool) public ProcessedTransactions;
    uint8 constant TRANSACTION_TYPE_WITHDRAW_BATTLEFLY = 0;
    uint8 constant TRANSACTION_TYPE_WITHDRAW_MAGIC = 1;
    uint8 constant TRANSACTION_TYPE_WITHDRAW_ITEM = 2;

    mapping(address => uint256) public usersLastWithdrawal;

    // Upgrade for Wastelands rewards

    IWastelands public WASTELANDS;

    // Upgrade for Open Beta launch

    struct PendingWithdrawal {
        address user;
        uint256 amount;
        uint256 transactionId;
        bool toBeProcessed;
    }

    mapping(address => bool) public pauseGuardians;
    bool public paused;
    uint256 public withdrawalLimit;
    uint256 public pendingWithdrawalCounter;
    mapping(uint256 => PendingWithdrawal) public pendingWithdrawals;

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
    function setMagic(address magicAddress) external onlyOwner {
        MagicToken = IERC20Upgradeable(magicAddress);
    }

    function setWithdrawalLimit(uint256 withdrawalLimit_) external onlyOwner {
        withdrawalLimit = withdrawalLimit_;
    }

    function setAdminAccess(address user, bool access) external onlyOwner {
        adminAccess[user] = access;
        emit SetAdminAccess(user, access);
    }

    function topupWastelandsRewards(uint256 amount) external onlyAdminAccess {
        require(!paused, "Contract paused");
        require(MagicToken.balanceOf(address(this)) >= amount, "Not enough Magic available");
        MagicToken.safeApprove(address(WASTELANDS), amount);
        WASTELANDS.topupMagicRewards(amount);
        emit WastelandsRewardsToppedUp(msg.sender, amount, block.timestamp);
    }

    function setWastelandsContract(address wastelands) external onlyOwner {
        require(wastelands != address(0), "Invalid address");
        WASTELANDS = IWastelands(wastelands);
    }

    function addPauseGuardian(address pauseGuardian) external onlyAdminAccess {
        require(!pauseGuardians[pauseGuardian],"Guardian already exists");
        pauseGuardians[pauseGuardian] = true;
        emit PauseGuardianAdded(pauseGuardian);
    }

    function removePauseGuardian(address pauseGuardian) external onlyAdminAccess {
        require(pauseGuardians[pauseGuardian],"Guardian does not exist");
        pauseGuardians[pauseGuardian] = false;
        emit PauseGuardianRemoved(pauseGuardian);
    }

    function processPendingWithdrawal(uint256 pendingId, bool authorize) external onlyOwner {
        require(pendingWithdrawals[pendingId].toBeProcessed, "Withdrawal is already processed");
        pendingWithdrawals[pendingId].toBeProcessed = false;
        uint256 amount = pendingWithdrawals[pendingId].amount;
        address user = pendingWithdrawals[pendingId].user;
        if(authorize) {
            MagicToken.safeTransfer(user, amount);
        }
        emit PendingWithdrawalProcessed(msg.sender, user, amount, pendingWithdrawals[pendingId].transactionId, pendingId, authorize, block.timestamp);
    }

    //Magic token
    function depositMagic(uint256 amount) external {
        MagicToken.safeTransferFrom(_msgSender(), address(this), amount);
        emit DepositMagic(amount, _msgSender(), block.timestamp);
    }

    function topupLeaderboardRewards(uint256 amount) external {
        MagicToken.safeTransferFrom(_msgSender(), address(this), amount);
        emit LeaderboardRewardsToppedUp(amount, _msgSender(), block.timestamp);
    }

    function claimWithdrawMagic(
        uint256 amount,
        uint256 transactionId,
        uint expiry,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        require(!paused, "Contract paused");
        require(ProcessedTransactions[transactionId] == false, "Transaction has already been processed");
        ProcessedTransactions[transactionId] = true;

        bytes32 payloadHash = keccak256(
            abi.encodePacked(_msgSender(), amount, transactionId, expiry, TRANSACTION_TYPE_WITHDRAW_MAGIC)
        );

        require(block.timestamp > usersLastWithdrawal[_msgSender()] + 15 minutes, "Withdrawal cooldown");
        require(block.timestamp < expiry, "Withdrawal expired");

        bytes32 messageHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", payloadHash));

        (address admin, ECDSAUpgradeable.RecoverError result) = ECDSAUpgradeable.tryRecover(messageHash, v, r, s);

        require(
            result == ECDSAUpgradeable.RecoverError.NoError && adminAccess[admin],
            "Signature not generated by admin or other signature error"
        );

        if(amount >= withdrawalLimit) {
            ++pendingWithdrawalCounter;
            pendingWithdrawals[pendingWithdrawalCounter] = PendingWithdrawal(_msgSender(),amount,transactionId,true);
            emit PendingWithdrawalCreated(amount, _msgSender(), transactionId, pendingWithdrawalCounter, block.timestamp);
        } else {
            MagicToken.safeTransfer(_msgSender(), amount);
            usersLastWithdrawal[_msgSender()] = block.timestamp;
            emit WithdrawMagic(amount, _msgSender(), block.timestamp, transactionId);
        }
    }

    function pause() external onlyPauseGuardians {
        paused = true;
        emit Paused();
    }

    function unpause() external onlyPauseGuardians {
        paused = false;
        emit Unpaused();
    }

    //modifier
    modifier onlyAdminAccess() {
        require(adminAccess[_msgSender()] == true || _msgSender() == owner(), "Require admin access");
        _;
    }

    modifier onlyPauseGuardians() {
        require(pauseGuardians[msg.sender] == true, "Not pause guardian");
        _;
    }
}

