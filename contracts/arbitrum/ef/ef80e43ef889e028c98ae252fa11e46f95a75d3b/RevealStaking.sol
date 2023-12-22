// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.2;

import "./OwnableUpgradeable.sol";
import "./SafeMathUpgradeable.sol";
import "./AddressUpgradeable.sol";
import "./EnumerableSetUpgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";
import "./IBattlefly.sol";
import "./SafeERC20Upgradeable.sol";
import "./IERC20Upgradeable.sol";
import "./ERC721HolderUpgradeable.sol";
import "./ECDSAUpgradeable.sol";
import "./IBattleflyGame.sol";




contract RevealStaking is ERC721HolderUpgradeable, OwnableUpgradeable, ReentrancyGuardUpgradeable {
    using SafeMathUpgradeable for uint256;
    using AddressUpgradeable for address;
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.UintSet;
    using SafeERC20Upgradeable for IERC20Upgradeable;
    mapping(address => bool) private adminAccess;
    IBattlefly private BattleflyContract;
    IERC20Upgradeable private MagicToken;
    uint256 public MagicAmountPerBattlefly;
    IBattleflyGame private BattleflyGame;
    mapping(address => EnumerableSetUpgradeable.UintSet) private StakingBattlefliesOfOwner;
    mapping(uint256 => address) public OwnerOfStakingBattlefly;
    mapping(uint256 => uint256) public MagicAmountOfStakingBattlefly;
    mapping(uint256 => bool) public NectarClaimed;

    uint8 constant COCOON_STAGE = 0;
    uint8 constant BATTLEFLY_STAGE = 1;

    uint8 constant NECTAR_ID = 0;

    event SetAdminAccess(address indexed user, bool access);
    event BulkStakeBattlefly(uint256[] tokenIds, address indexed user, uint256 totalMagicAmount);
    event BulkUnstakeBattlefly(uint256[]  tokenIds, address indexed user,  uint256 totalMagicAmount);

    function initialize(address batteflyGameContractAddress, address battleflyContractAddress, address magicTokenAddress, uint256 _MagicAmountPerBattlefly) public initializer {
        __ERC721Holder_init();
        __Ownable_init();
        __ReentrancyGuard_init();
        BattleflyContract = IBattlefly(battleflyContractAddress);
        MagicToken = IERC20Upgradeable(magicTokenAddress);
        MagicAmountPerBattlefly = _MagicAmountPerBattlefly;
        BattleflyGame = IBattleflyGame(batteflyGameContractAddress);
    }
    // ADMIN
    function setAdminAccess(address user, bool access) external onlyOwner {
        adminAccess[user] = access;
        emit SetAdminAccess(user, access);
    }
    //USER
    function stakingBattlefliesOfOwner(address user) external view returns (uint256[] memory) {
        return StakingBattlefliesOfOwner[user].values();
    }
    function bulkStakeBattlefly(uint256[] memory tokenIds) external nonReentrant {
        for(uint256 i = 0; i < tokenIds.length; i++) {
            uint256 tokenId = tokenIds[i];
            OwnerOfStakingBattlefly[tokenId] = _msgSender();
            MagicAmountOfStakingBattlefly[tokenId] = MagicAmountPerBattlefly;
            StakingBattlefliesOfOwner[_msgSender()].add(tokenId);
            BattleflyContract.safeTransferFrom(_msgSender(), address(this), tokenId);
        }
        uint256 totalMagicAmount = MagicAmountPerBattlefly.mul(tokenIds.length);
        MagicToken.safeTransferFrom(_msgSender(), address(this), totalMagicAmount);
        emit BulkStakeBattlefly(tokenIds, _msgSender(), totalMagicAmount);
    }
    function bulkUnstakeBattlefly(uint256[] memory tokenIds, uint256[] memory battleflyStages,  uint8 v, bytes32 r, bytes32 s) external nonReentrant {
        uint256 totalMagicAmount = 0;
        uint256 totalNectar = 0;
        address receiver = _msgSender();
        bytes32 payloadHash = keccak256(abi.encodePacked(tokenIds, battleflyStages));
        bytes32 messageHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", payloadHash));
        (address admin, ECDSAUpgradeable.RecoverError result) =  ECDSAUpgradeable.tryRecover(messageHash, v, r, s);
        require(result == ECDSAUpgradeable.RecoverError.NoError && adminAccess[admin], "Require admin access");
        for(uint256 i = 0; i< tokenIds.length; i++) {
            uint256 tokenId = tokenIds[i];
            require(OwnerOfStakingBattlefly[tokenId] == _msgSender(), "Require Staking Battlefly owner access");
            OwnerOfStakingBattlefly[tokenId] = address(0);
            totalMagicAmount = totalMagicAmount.add(MagicAmountOfStakingBattlefly[tokenId]);
            MagicAmountOfStakingBattlefly[tokenId] = 0;
            StakingBattlefliesOfOwner[_msgSender()].remove(tokenId);
            if(battleflyStages[i] ==  BATTLEFLY_STAGE && NectarClaimed[tokenId] == false) {
                NectarClaimed[tokenId] = true;
                totalNectar = totalNectar.add(5);
            }
            BattleflyContract.safeTransferFrom(address(this), receiver, tokenId);
        }
        if(totalMagicAmount != 0)
            MagicToken.safeTransfer(receiver, totalMagicAmount);
        if(totalNectar != 0) 
            BattleflyGame.mintItems(NECTAR_ID, receiver, totalNectar);
        emit BulkUnstakeBattlefly(tokenIds, receiver, totalMagicAmount);
    }
    //modifier
    modifier onlyAdminAccess() {
        require(adminAccess[_msgSender()] == true || _msgSender() == owner(), "Require admin access");
        _;
    }
}
