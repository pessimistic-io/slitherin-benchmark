// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.9;

import "./baseContract.sol";
import "./IUser.sol";
import "./IBNFT.sol";
import "./IERC20Mintable.sol";
import "./IERC20MetadataUpgradeable.sol";
import "./IERC721Upgradeable.sol";
import "./ERC721EnumerableUpgradeable.sol";
// Uncomment this line to use console.log
// import "hardhat/console.sol";

contract User is IUser, baseContract {

    mapping(address => UserInfo) public userInfoOf;
    mapping(uint256 => StakeInfo) public stakeNFTs;
    mapping(address => uint256) public contributionOf;
    mapping(address => uint256) public achievementCounter;

    event Register(address indexed account, address ref);
    event LevelUp(address indexed account, Level level);
    event ClaimAchievementReward(address indexed account, uint256 indexed nftId, uint256 amount);

    event SocialRewardDistribute(address indexed account, address invitee, uint256 amount);
    event CommunityRewardDistribute(address indexed account, address invitee, uint256 amount);
    event ContributionRewardDistribute(address indexed account, address invitee, uint256 amount);

    struct UserInfo {
        Level level;
        address refAddress;
        uint256 stakeRev;
        uint256 socialRev;
        uint256 communityRev;
        uint256 contributionRev;
        uint256 achievementRev;
        uint256 performance;
        mapping(uint256 => uint256) refCounterOf;
    }

    struct StakeInfo {
        uint256 lastUpdateTime;
        uint256 stakedDuration;
    }

    constructor(address dbAddress) baseContract(dbAddress) {

    }

    function __User_init() public initializer {
        __baseContract_init();
        __User_init_unchained();
    }

    function __User_init_unchained() private {
    }

    function registerByEarlyPlan(address _userAddr, address _refAddr) external onlyLYNKNFTOrDBContract {
        require(userInfoOf[_userAddr].refAddress == address(0), 'User: already register.');

        _register(_userAddr, _refAddr);
    }

    function register(address _refAddr) external {
        // require(DBContract(DB_CONTRACT).commonMintEnable(), 'User: cannot register yet.');

        _register(_msgSender(), _refAddr);
    }

    function _register(address _userAddr, address _refAddr) private {
        require(
            userInfoOf[_userAddr].refAddress == address(0) &&
            _userAddr != DBContract(DB_CONTRACT).rootAddress(),
                'User: already register.'
        );
        require(
            userInfoOf[_refAddr].refAddress != address(0) ||
            _refAddr == DBContract(DB_CONTRACT).rootAddress(),
                'User: the ref not a valid ref address.'
        );

        userInfoOf[_userAddr].refAddress = _refAddr;
        userInfoOf[_refAddr].refCounterOf[0] += 1;
        emit Register(_userAddr, _refAddr);

        // _auditLevel(_refAddr);
    }

    function isValidUser(address _userAddr) view external returns (bool) {
        return userInfoOf[_userAddr].refAddress != address(0);
    }

    function hookByUpgrade(address _userAddr, uint256 _performance) onlyLYNKNFTContract external {
        _hookByUpgrade(_userAddr, _performance);
    }

    function hookByStake(uint256 nftId) onlyStakingContract external {
        stakeNFTs[nftId].lastUpdateTime = block.timestamp;
    }

    function hookByUnStake(uint256 nftId) onlyStakingContract external {
        uint256 lastUpdateTime = stakeNFTs[nftId].lastUpdateTime;
        stakeNFTs[nftId].lastUpdateTime = block.timestamp;
        if (DBContract(DB_CONTRACT).hasAchievementReward(nftId)) {
            stakeNFTs[nftId].stakedDuration += block.timestamp - lastUpdateTime;
        }
    }

    function hookByClaimReward(address _userAddr, uint256 _rewardAmount) onlyStakingContract external {
        address curAddr = userInfoOf[_userAddr].refAddress;
        address lynkAddr = DBContract(DB_CONTRACT).LRT_TOKEN();
        uint256 maxInvitationLevel = DBContract(DB_CONTRACT).maxInvitationLevel();
        for (uint256 index; index < maxInvitationLevel; index++) {
            if (curAddr == address(0)) break;

            uint256 rate = DBContract(DB_CONTRACT).communityRewardRate(userInfoOf[curAddr].level, index);
            if (rate > 0) {
                uint256 reward = rate * _rewardAmount / 1e18;

                userInfoOf[curAddr].communityRev += reward;
                IERC20Mintable(lynkAddr).mint(curAddr, reward);
                emit CommunityRewardDistribute(curAddr, _userAddr, reward);
            }

            curAddr = userInfoOf[curAddr].refAddress;
        }

        userInfoOf[_userAddr].stakeRev += _rewardAmount;
    }

    function claimAchievementReward(uint256 _nftId) external {
        address LYNKNFTAddress = DBContract(DB_CONTRACT).LYNKNFT();
        address bLYNKNFTAddress = DBContract(DB_CONTRACT).STAKING_LYNKNFT();

        require(
            IERC721Upgradeable(LYNKNFTAddress).ownerOf(_nftId) == _msgSender() ||
            IERC721Upgradeable(bLYNKNFTAddress).ownerOf(_nftId) == _msgSender(),
                'User: not the owner.'
        );

        uint256 rewardAmount = _calcAchievementReward(_msgSender(), _nftId);

        require(rewardAmount > 0, 'User: cannot claim 0.');
        stakeNFTs[_nftId].stakedDuration = 0;
        stakeNFTs[_nftId].lastUpdateTime = block.timestamp;

        achievementCounter[_msgSender()]++;
        userInfoOf[_msgSender()].achievementRev += rewardAmount;
        IERC20Mintable(DBContract(DB_CONTRACT).AP_TOKEN()).mint(_msgSender(), rewardAmount);

        emit ClaimAchievementReward(_msgSender(), _nftId, rewardAmount);
    }

    function auditLevel(address _userAddr) external {
        _auditLevel(_userAddr);
    }

    function calcAchievementReward(address _userAddr, uint256 _nftId) external view returns (uint256) {
        return _calcAchievementReward(_userAddr, _nftId);
    }

    function levelUpAble(address _userAddr) external view returns (bool) {
        return _levelUpAble(_userAddr);
    }

    function _auditLevel(address _userAddr) private {
        require(
            userInfoOf[_userAddr].refAddress != address(0) ||
            _userAddr == DBContract(DB_CONTRACT).rootAddress(),
                'User: not a valid user.'
        );

        uint256 curLevelIndex = uint256(userInfoOf[_userAddr].level);
        if (_levelUpAble(_userAddr)) {
            Level nextLevelIndex = Level(curLevelIndex + 1);
            userInfoOf[_userAddr].level = nextLevelIndex;
            emit LevelUp(_userAddr, nextLevelIndex);

            address refAddress = userInfoOf[_userAddr].refAddress;
            if (refAddress != address(0)) {
                userInfoOf[refAddress].refCounterOf[uint256(nextLevelIndex)] += 1;
            }
        }
    }

    function _levelUpAble(address _userAddr) private view returns (bool) {
        uint256 curLevelIndex = uint256(userInfoOf[_userAddr].level);
        if (curLevelIndex < uint256(type(Level).max)) {
            uint256 directRequire = DBContract(DB_CONTRACT).directRequirements(curLevelIndex);
            uint256 performanceRequire = DBContract(DB_CONTRACT).performanceRequirements(curLevelIndex);
            if (
                userInfoOf[_userAddr].performance >= performanceRequire &&
                userInfoOf[_userAddr].refCounterOf[curLevelIndex] >= directRequire
            ) {
                return true;
            }
        }

        return false;
    }

    function _calcAchievementReward(address _userAddr, uint256 _nftId) private view returns (uint256) {
        uint256 durationThreshold = DBContract(DB_CONTRACT).achievementRewardDurationThreshold();
        uint256 rewardAmount = DBContract(DB_CONTRACT).achievementRewardAmounts(uint256(userInfoOf[_userAddr].level));

        address LYNKNFTAddress = DBContract(DB_CONTRACT).LYNKNFT();
        address sLYNKNFTAddress = DBContract(DB_CONTRACT).STAKING_LYNKNFT();
        uint256 rewardTotalAmount;
        if (DBContract(DB_CONTRACT).hasAchievementReward(_nftId)) {
            uint256 duration = block.timestamp - stakeNFTs[_nftId].lastUpdateTime;
            if (IERC721Upgradeable(LYNKNFTAddress).ownerOf(_nftId) != sLYNKNFTAddress) {
                duration = 0;
            }
            if (stakeNFTs[_nftId].stakedDuration + duration >= durationThreshold) {
                rewardTotalAmount = rewardAmount;
            }
        }

        return rewardTotalAmount;
    }

    function refCounterOf(address _userAddr, Level _level) external view returns (uint256) {
        return userInfoOf[_userAddr].refCounterOf[uint256(_level)];
    }

    function _autoLevel(address _userAddr, uint256 _level) private {
       require(
            userInfoOf[_userAddr].refAddress != address(0) ||
            _userAddr == DBContract(DB_CONTRACT).rootAddress(),
                'User: not a valid user.'
        );
        require(_level>=0 && _level<6,"User: level error");
        uint256 curLevelIndex = uint256(userInfoOf[_userAddr].level);
        if(_level>curLevelIndex){
            Level nextLevelIndex = Level(_level);
            userInfoOf[_userAddr].level = nextLevelIndex;
            emit LevelUp(_userAddr, nextLevelIndex);

            address refAddress = userInfoOf[_userAddr].refAddress;
            if (refAddress != address(0)) {
                userInfoOf[refAddress].refCounterOf[uint256(nextLevelIndex)] += 1;
            }
        }
    }

    function _mintAP(address _userAddr, uint256 _amount) private {
        if (_userAddr != address(0)) {
            IERC20Mintable(DBContract(DB_CONTRACT).AP_TOKEN()).mint(_userAddr, _amount);
        }
    }

    function nodeReward(address _userAddr,uint256 ap,uint256 level,uint256 ca)  external onlyLYNKNFTContract {
        uint256 mintAP = ap * (10 ** IERC20MetadataUpgradeable(DBContract(DB_CONTRACT).AP_TOKEN()).decimals());
        _mintAP(_userAddr,mintAP);
        _autoLevel(_userAddr,level);
        _hookByUpgrade(_userAddr,ca);
    }

    function _hookByUpgrade(address _userAddr, uint256 _performance) private {
        if (_performance > 0) {
            address _refAddr = userInfoOf[_userAddr].refAddress;
            uint256 _refLevel = uint256(userInfoOf[_refAddr].level);

            uint256 amount;
            // distribute social reward
            uint256 rate = DBContract(DB_CONTRACT).socialRewardRates(_refLevel);
            amount = (_performance * (10 ** IERC20MetadataUpgradeable(DBContract(DB_CONTRACT).LRT_TOKEN()).decimals()) * rate) / 1e18;
            userInfoOf[_refAddr].socialRev += amount;
            IERC20Mintable(DBContract(DB_CONTRACT).LRT_TOKEN()).mint(_refAddr, amount);
            emit SocialRewardDistribute(_refAddr, _userAddr, amount);

            // distribute contribution reward
            uint256 threshold = DBContract(DB_CONTRACT).contributionRewardThreshold();
            if (threshold > 0) {
                uint256 _contribution = contributionOf[_refAddr];
                amount = (((_contribution + _performance) / threshold) - (_contribution / threshold)) * DBContract(DB_CONTRACT).contributionRewardAmounts(_refLevel);
                if (amount > 0) {
                    userInfoOf[_refAddr].contributionRev += amount;
                    IERC20Mintable(DBContract(DB_CONTRACT).AP_TOKEN()).mint(_refAddr, amount);
                    emit ContributionRewardDistribute(_refAddr, _userAddr, amount);
                }
            }
            contributionOf[_refAddr] += _performance;

            address currentAddress = _refAddr;
            uint256 performanceThreshold = DBContract(DB_CONTRACT).performanceThreshold();
            for (uint256 index = 0; index < performanceThreshold; index++) {
                if (currentAddress == address(0)) {
                    break;
                }
                userInfoOf[currentAddress].performance += _performance;
                currentAddress = userInfoOf[currentAddress].refAddress;
            }
            // _auditLevel(_refAddr);
        }
    }

    function setLevel(address _userAddr, uint256 _level) external onlyOperator {
       require(
            userInfoOf[_userAddr].refAddress != address(0) ||
            _userAddr == DBContract(DB_CONTRACT).rootAddress(),
                'User: not a valid user.'
        );
        require(_level>=0 && _level<6,"User: level error");
        uint256 curLevelIndex = uint256(userInfoOf[_userAddr].level);
        if(_level>curLevelIndex){
            Level nextLevelIndex = Level(_level);
            userInfoOf[_userAddr].level = nextLevelIndex;
            emit LevelUp(_userAddr, nextLevelIndex);

            address refAddress = userInfoOf[_userAddr].refAddress;
            if (refAddress != address(0)) {
                userInfoOf[refAddress].refCounterOf[uint256(nextLevelIndex)] += 1;
            }
        }
    }
}

