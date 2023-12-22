// SPDX-License-Identifier: MIT
pragma solidity >=0.8.9 <0.9.0;


import "./IERC721Upgradeable.sol";
import "./ERC1155Upgradeable.sol";
import "./ERC1155HolderUpgradeable.sol";
import "./ERC721HolderUpgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./Initializable.sol";
import "./UUPSUpgradeable.sol";


interface IBossCardERC1155{
    function safeTransferFrom(address from, address to, uint id, uint amount, bytes memory data) external;
}

interface IIngredientsERC1155{
    function safeTransferFrom(address from, address to, uint id, uint amount, bytes memory data) external;
    function mint(address to, uint256 id, uint256 value) external;
    function mintBatch(address to, uint256[] memory ids, uint256[] memory values) external;
}

interface ICommonConst {
    function revealIngredientNftId() external returns(uint256);
}
interface IErrandBossCardStake {
    function getBossCountClaim(address account,uint256 time) external view returns(uint);
    function getUserStakeBossCardId(address _account) external returns(uint);
}

contract ErrandGen0 is Initializable, ERC1155HolderUpgradeable, ReentrancyGuardUpgradeable, OwnableUpgradeable, UUPSUpgradeable,ERC721HolderUpgradeable {
    ICommonConst commonConst;
    IErrandBossCardStake errandBossCardStake;
    IERC721Upgradeable private powerPlinsGen0;
    address private bossCardERC1155;
    address private ingredientsERC1155;

   struct RecipeStaker {
        uint[] tokenIds;
        uint256  time;
    }
    mapping(uint256 => RecipeStaker) public recipeStakers;
    mapping(address => uint[]) public userStakeIds;

    mapping(address => mapping(uint256 => uint256))  tokenIdToRewardsClaimed;
    uint256 stakeIdCount;
    uint256  public timeForReward;
    uint256 totalTokenStake;

    /* ========== EVENTS ========== */

    event Staked(address indexed user, uint256 amount, uint256[] tokenIds);
    event Withdrawn(address indexed user, uint256 amount, uint256[] tokenIds);
    event RewardClaimed(
        address indexed user,
        uint256 _claimedRewardId,
        uint[] ingredientNftIds
    );

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _powerPlinsGen0, address _ingredientsERC1155,address _bossCard, address _commonConst, address _errandBossCardStake) external initializer {
        __ReentrancyGuard_init();
        __Ownable_init();
        __ERC721Holder_init();
        powerPlinsGen0 = IERC721Upgradeable(_powerPlinsGen0);
        ingredientsERC1155 = _ingredientsERC1155;
        bossCardERC1155 = _bossCard;
        stakeIdCount = 1;
        timeForReward = 8 hours;
        commonConst = ICommonConst(_commonConst);
        errandBossCardStake = IErrandBossCardStake(_errandBossCardStake);
        totalTokenStake=0;
    }

    function setTimeForReward(uint256 _timeForReward) public onlyOwner {
        timeForReward = _timeForReward;
    }
    function indexOf(uint[] memory self, uint value) internal pure returns (int) {
        for (uint i = 0; i < self.length; i++)if (self[i] == value) return int(i);
        return -1;
    }

    function stake(uint256[] memory _tokenIds) external nonReentrant{
        require(_tokenIds.length != 0, "Errand:: invalid ids");
        for (uint i = 0; i < _tokenIds.length; i++) {
            powerPlinsGen0.safeTransferFrom(msg.sender, address(this), _tokenIds[i]);
        }
        recipeStakers[stakeIdCount] = RecipeStaker({
            tokenIds:_tokenIds,
            time: block.timestamp
        });
        userStakeIds[msg.sender].push(stakeIdCount);
        stakeIdCount++;
        totalTokenStake += _tokenIds.length;

        emit Staked(msg.sender, _tokenIds.length, _tokenIds);
    }

    function unStake(uint256 _stakeId) public nonReentrant {
        require(indexOf(userStakeIds[msg.sender],_stakeId) >=0,"Errand: not valid unstake id");
        RecipeStaker memory recipeStake = recipeStakers[_stakeId];

        uint _numberToClaim =  numberOfRewardsToClaim(_stakeId, recipeStake.time, recipeStake.tokenIds.length);
        require( _numberToClaim == 0,"Errand:: rewards left unclaimed!");

        uint256 amount = recipeStake.tokenIds.length;
        for (uint256 i = 0; i < amount; i++) {
            powerPlinsGen0.safeTransferFrom(address(this),msg.sender, recipeStake.tokenIds[i]);
        }
        delete tokenIdToRewardsClaimed[msg.sender][_stakeId];
        delete recipeStakers[_stakeId];
        for(uint i=0 ; i < userStakeIds[msg.sender].length; i++) {
            if(userStakeIds[msg.sender][i] == _stakeId){
                while ( i < userStakeIds[msg.sender].length - 1) {
                    userStakeIds[msg.sender][i] = userStakeIds[msg.sender][i+1];
                    i++;
                }
                userStakeIds[msg.sender].pop();
            }
        }
        totalTokenStake -= amount;
        emit Withdrawn(msg.sender, amount, recipeStake.tokenIds);
    }

    function numberOfRewardsToClaim(uint256 _stakeId, uint256 stakeTime , uint tokens) public  view returns (uint) {
        uint256 lastClaimTime = stakeTime +  (tokenIdToRewardsClaimed[msg.sender][_stakeId] * timeForReward);
        if(lastClaimTime == 0) {
            return 0;
        }
        uint count = (block.timestamp - lastClaimTime)  / (timeForReward * 3);
        uint bossCount = errandBossCardStake.getBossCountClaim(msg.sender,lastClaimTime);
        uint totalCount = count > 0 ? (count*3*tokens) + bossCount*tokens : 0;
        return totalCount;
    }

    function claimReward(uint256 _stakeId) public nonReentrant {
        require(indexOf(userStakeIds[msg.sender],_stakeId) >=0,"Errand: not valid unstake id");
        RecipeStaker memory staker = recipeStakers[_stakeId];
        uint256[] memory tokenIds = staker.tokenIds;
        require(recipeStakers[_stakeId].tokenIds.length != 0, "claimReward: No token Found for claim");

        uint _numberToClaim =  numberOfRewardsToClaim(_stakeId, recipeStakers[_stakeId].time,1);
        require(_numberToClaim != 0, "claimReward: No claim pending");

        _claimReward(_numberToClaim*tokenIds.length, _stakeId);
        uint256 lastClaimTime = recipeStakers[_stakeId].time +  (tokenIdToRewardsClaimed[msg.sender][_stakeId] * timeForReward);
        uint bossCount = errandBossCardStake.getBossCountClaim(msg.sender,lastClaimTime);
        tokenIdToRewardsClaimed[msg.sender][_stakeId] += (_numberToClaim - bossCount);
    }


    function _claimReward(uint _numClaim, uint _stakeId) private {
        if(_numClaim > 999){
            _numClaim = 999;
        }
        uint[] memory ingredientNftIds = new uint[](_numClaim);
        uint[] memory amounts = new uint[](_numClaim);
        for(uint i = 0; i<_numClaim;i++){
            uint nftId = commonConst.revealIngredientNftId();
            ingredientNftIds[i] = nftId;
            amounts[i] = 1;
        }
        IIngredientsERC1155(ingredientsERC1155).mintBatch(msg.sender,ingredientNftIds, amounts);
        emit RewardClaimed(msg.sender, _stakeId, ingredientNftIds);
    }

    function anyClaimInProgress() public  view returns (bool) {
        bool flag = false;
        uint[] memory stakeIds = userStakeIds[msg.sender];
        for(uint256 i =0; i < stakeIds.length; i++ ){
            RecipeStaker memory staker = recipeStakers[stakeIds[i]];
            uint256 count = numberOfRewardsToClaim(stakeIds[i], staker.time,staker.tokenIds.length);
            if(count > 0){
                flag = true;
                break;
            }
        }
        return flag;
    }

    function printUserClaims() public  view returns (uint256[] memory, uint[] memory) {
        uint[] memory stakeIds = userStakeIds[msg.sender];
        uint256[] memory claims = new uint256[](stakeIds.length);
        for(uint256 i =0; i < stakeIds.length; i++ ){
            RecipeStaker memory recipeStake = recipeStakers[stakeIds[i]];
            claims[i] =  numberOfRewardsToClaim(stakeIds[i], recipeStake.time,recipeStake.tokenIds.length);
        }

        return(stakeIds, claims);
    }

    function printUserStakes() public  view returns (uint[] memory,RecipeStaker[] memory) {
        uint[] memory stakeIds = userStakeIds[msg.sender];
        RecipeStaker[] memory stakes = new RecipeStaker[](stakeIds.length);
        for(uint256 i =0; i < stakeIds.length; i++ ){
            stakes[i] = recipeStakers[stakeIds[i]];
        }
        return(stakeIds, stakes);
    }

    function  printTotalTokenStake() public view returns(uint256){
        return totalTokenStake;
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}
}

