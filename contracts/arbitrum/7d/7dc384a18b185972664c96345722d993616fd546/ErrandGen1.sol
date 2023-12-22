// SPDX-License-Identifier: MIT

pragma solidity >=0.8.9 <0.9.0;

import "./IERC1155Upgradeable.sol";
import "./ERC1155Upgradeable.sol";
import "./ERC1155HolderUpgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./StringsUpgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";
import "./PausableUpgradeable.sol";
import "./Initializable.sol";
import "./UUPSUpgradeable.sol";
import "./console.sol";

interface ICommonConst {
    function revealIngredientNftId() external returns(uint256);
}

interface IGen1ERC1155{
    function safeTransferFrom(address from, address to, uint id, uint amount, bytes memory data) external;
}

interface IIngredientsERC1155{
    function safeTransferFrom(address from, address to, uint id, uint amount, bytes memory data) external;
    function mint(address to, uint256 id, uint256 value) external;
    function mintBatch(address to, uint256[] memory ids, uint256[] memory values) external;
}

interface IErrandBossCardStake {
    function getBossCountClaim(address account,uint256 time) external view returns(uint);
    function getUserStakeBossCardId(address _account) external view returns(uint);
}

contract ErrandGen1 is Initializable, OwnableUpgradeable, ERC1155HolderUpgradeable,ReentrancyGuardUpgradeable, PausableUpgradeable, UUPSUpgradeable{
    uint256 stakeIdCount;
    uint256 public timeForReward;
    address private powerPlinsGen1;
    address private ingredientsERC1155;
    ICommonConst commonConst;
    IErrandBossCardStake errandBossCardStake;

    struct Gen1Stake {
        uint256 stakeId;
        uint[] tokenIds;
        uint256  time;
    }

    mapping(uint256 => Gen1Stake) private gen1Stakes;
    mapping(address => uint[]) private userGen1StakeIds;

    mapping(address => mapping(uint256 => uint256))  private tokenIdToRewardsClaimed;
    uint256 totalTokenStake;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /* ========== EVENTS ========== */

    event Staked(address indexed user, uint256 amount, uint256[] tokenIds);
    event Withdrawn(address indexed user, uint256 amount, uint256[] tokenIds);
    event RewardClaimed(
        address indexed user,
        uint256 _claimedRewardId,
        uint[] ingredientNftIds
    );

    function initialize(address _powerPlinsGen1, address _ingredientsERC1155, address _commonConstGen1, address _errandBossCardStake) external initializer {
        __Ownable_init();
        __ReentrancyGuard_init();
        __Pausable_init();
        __UUPSUpgradeable_init();
        __ERC1155Holder_init();
        powerPlinsGen1 = _powerPlinsGen1;
        ingredientsERC1155 = _ingredientsERC1155;
        commonConst = ICommonConst(_commonConstGen1);
        stakeIdCount = 1;
        timeForReward = 24 hours;
        totalTokenStake=0;
        errandBossCardStake = IErrandBossCardStake(_errandBossCardStake);
    }

    function setTimeForReward(uint256 _timeForReward) public{
        timeForReward = _timeForReward;
    }
    function indexOf(uint[] memory self, uint value) internal pure returns (int) {
        for (uint i = 0; i < self.length; i++)if (self[i] == value) return int(i);
        return -1;
    }

    function stake(uint256[] memory _tokenIds) external nonReentrant whenNotPaused{
        require(_tokenIds.length != 0, "Staking: No tokenIds provided");
        uint256 amount;
        for (uint256 i = 0; i < _tokenIds.length; i += 1) {
            amount += 1;
            IGen1ERC1155(powerPlinsGen1).safeTransferFrom(msg.sender, address(this), _tokenIds[i],1,'');
        }
        gen1Stakes[stakeIdCount].tokenIds = _tokenIds;
        gen1Stakes[stakeIdCount].time = block.timestamp;
        userGen1StakeIds[msg.sender].push(stakeIdCount++);
        totalTokenStake += amount;
        emit Staked(msg.sender, amount, _tokenIds);
    }

    function unStack(uint256 _stakeId) public nonReentrant {
        require(indexOf(userGen1StakeIds[msg.sender],_stakeId) >=0,"Errand: not valid unstake id");
        Gen1Stake memory staker = gen1Stakes[_stakeId];

        uint256[] memory tokenIds =  staker.tokenIds;
        uint _numberToClaim =  numberOfRewardsToClaim(_stakeId, staker.time, staker.tokenIds.length);
        require( _numberToClaim == 0,"Rewards left unclaimed!");

        uint256 amount = staker.tokenIds.length;
        for (uint256 i = 0; i < amount; i += 1) {
            IGen1ERC1155(powerPlinsGen1).safeTransferFrom(address(this),msg.sender, tokenIds[i], 1, '');
        }
        delete tokenIdToRewardsClaimed[msg.sender][_stakeId];
        delete gen1Stakes[_stakeId];
        for(uint i=0 ; i < userGen1StakeIds[msg.sender].length; i++) {
            if(userGen1StakeIds[msg.sender][i] == _stakeId){
                while ( i < userGen1StakeIds[msg.sender].length - 1) {
                    userGen1StakeIds[msg.sender][i] = userGen1StakeIds[msg.sender][i+1];
                    i++;
                }
                userGen1StakeIds[msg.sender].pop();
            }
        }
        totalTokenStake -= amount;
        emit Withdrawn(msg.sender, amount, tokenIds);
    }



    function numberOfRewardsToClaim(uint256 _stakeId, uint256 stakeTime , uint tokens) public  view returns (uint) {
        uint256 stakedTime = stakeTime +  (tokenIdToRewardsClaimed[msg.sender][_stakeId] * timeForReward);
        if(stakedTime == 0) {
            return 0;
        }
        uint count = (block.timestamp - stakedTime)  / timeForReward;
        uint bossCount = errandBossCardStake.getBossCountClaim(msg.sender,stakedTime);
        uint totalCount = count > 0 ? (count* tokens) + bossCount*tokens : 0;
        return totalCount;
    }

    function claimReward(uint256 _stakeId) public {
        require(indexOf(userGen1StakeIds[msg.sender],_stakeId) >=0,"Errand: not valid stake id for claim");
        Gen1Stake memory staker = gen1Stakes[_stakeId];
        uint _numberToClaim =  numberOfRewardsToClaim(_stakeId, staker.time,1);
        require(_numberToClaim != 0, "claimReward: No claim pending");
        _claimReward(_numberToClaim*staker.tokenIds.length, _stakeId);
        uint256 lastClaimTime = staker.time +  (tokenIdToRewardsClaimed[msg.sender][_stakeId] * timeForReward);
        uint bossCount = errandBossCardStake.getBossCountClaim(msg.sender,lastClaimTime);
        tokenIdToRewardsClaimed[msg.sender][_stakeId] += (_numberToClaim - bossCount);
        //tokenIdToRewardsClaimed[msg.sender][_stakeId] += _numberToClaim;
    }

    function _claimReward(uint _numClaim, uint _stakeId) private {
        uint[] memory ingredientNftIds = new uint[](_numClaim);
        uint[] memory amounts = new uint[](_numClaim);
        for(uint i = 0; i<_numClaim;i++){
            uint nftId = commonConst.revealIngredientNftId();
            ingredientNftIds[i] = nftId;
            amounts[i] = 1;
        }
        IIngredientsERC1155(ingredientsERC1155).mintBatch(msg.sender,ingredientNftIds, amounts);
        emit RewardClaimed(msg.sender,  _stakeId, ingredientNftIds);
    }

    function anyClaimInProgress() public  view returns (bool) {
        bool flag = false;
        uint[] memory stakeIds = userGen1StakeIds[msg.sender];
        for(uint i =0; i < stakeIds.length;i++){
            Gen1Stake memory st = gen1Stakes[stakeIds[i]];
            uint256 count = numberOfRewardsToClaim(stakeIds[i], st.time,st.tokenIds.length);
            if(count > 0){
                flag = true;
                break;
            }
        }
        return flag;
    }

    function printUserGen1Claims() public  view returns (uint256[] memory, uint[] memory) {
        uint[] memory stakeIds = userGen1StakeIds[msg.sender];
        uint256[] memory claims = new uint256[](stakeIds.length);
        for(uint256 i =0; i < stakeIds.length; i++ ){
            Gen1Stake memory st = gen1Stakes[stakeIds[i]];
            claims[i] =  numberOfRewardsToClaim(stakeIds[i], st.time,st.tokenIds.length);
        }
        return(stakeIds, claims);
    }

    function printUserGen1Stakes() public view returns(uint[] memory,Gen1Stake[] memory){
        uint[] memory stakeIds = userGen1StakeIds[msg.sender];
        Gen1Stake[] memory stakes = new Gen1Stake[](stakeIds.length);
        for(uint256 i =0; i < stakeIds.length; i++ ){
            stakes[i] = gen1Stakes[stakeIds[i]];
        }
        return(stakeIds, stakes);
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}
    function  printTotalTokenStake() public view returns(uint256){
        return totalTokenStake;
    }
}

