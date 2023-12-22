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
    function getRandomIngredientId() external returns(uint256);
}

contract Errand_UP is Initializable, ERC1155HolderUpgradeable, ReentrancyGuardUpgradeable, OwnableUpgradeable, UUPSUpgradeable,ERC721HolderUpgradeable {
    ICommonConst commonConst;
    IERC721Upgradeable private powerPlinsGen0;
    address private bossCardERC1155;
    address private ingredientsERC1155;

    struct BossCardStaker{
        uint tokenId;
        bool isLegendary;
        uint256  time;
    }
    mapping(address => BossCardStaker)  public bossCardStakers;

    struct RecipeStaker {
        uint256 stakeId;
        uint[] tokenIds;
        uint256  time;
    }
    mapping(address => RecipeStaker[]) public recipeStakers;

    mapping(address => mapping(uint256 => uint256))  tokenIdToRewardsClaimed;
    uint256 stakeIdCount;
    uint256  public _timeForReward;

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

    function initialize(address _powerPlinsGen0, address _ingredientsERC1155,address _bossCard, address _commonConst) external initializer {
        __ReentrancyGuard_init();
        __Ownable_init();
        __ERC721Holder_init();
        powerPlinsGen0 = IERC721Upgradeable(_powerPlinsGen0);
        ingredientsERC1155 = _ingredientsERC1155;
        bossCardERC1155 = _bossCard;
        stakeIdCount = 1;
        _timeForReward = 60;
        commonConst = ICommonConst(_commonConst);
        __Ownable_init();
    }

    function stake(uint256[] memory tokenIds) external nonReentrant{
        require(tokenIds.length != 0, "Errand:: invalid ids");
        for (uint i = 0; i < tokenIds.length; i++) {
            powerPlinsGen0.safeTransferFrom(msg.sender, address(this), tokenIds[i]);
        }
        recipeStakers[msg.sender].push(RecipeStaker({
        stakeId:stakeIdCount++,
        tokenIds:tokenIds,
        time: block.timestamp
        }));

        emit Staked(msg.sender, tokenIds.length, tokenIds);
    }

    function unStake(uint256 _stakeId) public nonReentrant {
        RecipeStaker memory staker = recipeStakers[msg.sender][findIndex(_stakeId)];
        require(staker.tokenIds.length != 0, "Errand:: invalid ids");

        uint _numberToClaim =  numberOfRewardsToClaim(_stakeId, staker.time, staker.tokenIds.length);
        require( _numberToClaim == 0,"Errand:: rewards left unclaimed!");

        uint256 amount = staker.tokenIds.length;
        for (uint256 i = 0; i < amount; i++) {
            powerPlinsGen0.safeTransferFrom(address(this),msg.sender, staker.tokenIds[i]);
        }
        delete tokenIdToRewardsClaimed[msg.sender][_stakeId];

        RecipeStaker[] memory stakers = recipeStakers[msg.sender];
        for(uint i=0 ; i < stakers.length; i++) {
            if(stakers[i].stakeId == _stakeId){
                while ( i < recipeStakers[msg.sender].length - 1) {
                    recipeStakers[msg.sender][i] = recipeStakers[msg.sender][i+1];
                    i++;
                }
                recipeStakers[msg.sender].pop();
            }
        }
        emit Withdrawn(msg.sender, amount, staker.tokenIds);
    }

    function bossCardStake(uint _tokenId, bool _isLegendary) external nonReentrant {
        require(
            bossCardStakers[msg.sender].tokenId ==0,
            "Boost token already stake"
        );
        bossCardStakers[msg.sender] = BossCardStaker({
        tokenId: _tokenId,
        isLegendary:_isLegendary,
        time: block.timestamp
        });
        IBossCardERC1155(bossCardERC1155).safeTransferFrom(msg.sender, address(this), _tokenId, 1,'');
    }

    function bossCardWithdraw(uint _tokenId) external nonReentrant{
        require(!anyClaimInProgress(), "Claim in progress");
        IBossCardERC1155(bossCardERC1155).safeTransferFrom(address(this), msg.sender,_tokenId, 1,'');
        delete bossCardStakers[msg.sender];
    }

    function getBossCountClaim(uint256 stakedTime) public view returns(uint){
        uint bossCount = 0;
        if(bossCardStakers[msg.sender].tokenId !=0){
            uint bossNumber = 2;
            if(bossCardStakers[msg.sender].isLegendary){
                bossNumber = 1;
            }
            bossCount = (((block.timestamp - stakedTime ) / (_timeForReward * 3))) * bossNumber;
        }
        return bossCount;

    }
    function numberOfRewardsToClaim(uint256 _stakeId, uint256 stakeTime , uint tokens) public  view returns (uint) {
        uint256 stakedTime = stakeTime +  (tokenIdToRewardsClaimed[msg.sender][_stakeId] * _timeForReward);
        if(stakedTime == 0) {
            return 0;
        }
        uint count = (block.timestamp - stakedTime)  / _timeForReward;
        uint totalCount = count > 0 ? (count* tokens) + getBossCountClaim(stakedTime): 0;
        return totalCount;
    }

    function claimReward(uint256 _stakeId) public nonReentrant {
        RecipeStaker memory staker = recipeStakers[msg.sender][findIndex(_stakeId)];
        uint256[] memory tokenIds = staker.tokenIds;
        uint256 stakeTime = staker.time;
        require(tokenIds.length != 0, "claimReward: No token Found for claim");

        uint _numberToClaim =  numberOfRewardsToClaim(_stakeId, stakeTime,1);
        require(_numberToClaim != 0, "claimReward: No claim pending");


        _claimReward(_numberToClaim*tokenIds.length, _stakeId);
        uint256 lastClaimTime = stakeTime +  (tokenIdToRewardsClaimed[msg.sender][_stakeId] * _timeForReward);
        tokenIdToRewardsClaimed[msg.sender][_stakeId] += (_numberToClaim - getBossCountClaim(lastClaimTime));
    }

    function setTimeForReward(uint256 timeForReward) public onlyOwner {
        _timeForReward = timeForReward;
    }

    function _claimReward(uint _numClaim, uint _stakeId) private {
        uint[] memory ingredientNftIds = new uint[](_numClaim);
        uint[] memory amounts = new uint[](_numClaim);
        for(uint i = 0; i<_numClaim;i++){
            uint nftId = commonConst.getRandomIngredientId();
            ingredientNftIds[i] = nftId;
            amounts[i] = 1;
        }
        IIngredientsERC1155(ingredientsERC1155).mintBatch(msg.sender,ingredientNftIds, amounts);
        emit RewardClaimed(msg.sender, _stakeId, ingredientNftIds);
    }

    function findIndex(uint value) internal view returns(uint) {
        uint i = 0;
        RecipeStaker[] memory stakers = recipeStakers[msg.sender];
        while (stakers[i].stakeId != value) {
            i++;
        }
        return i;
    }

    function anyClaimInProgress() public  view returns (bool) {
        bool flag = false;
        RecipeStaker[] memory stakers = recipeStakers[msg.sender];
        for(uint256 i =0; i < stakers.length; i++ ){
            uint256 stakeTime =  stakers[i].time;
            uint256 count = numberOfRewardsToClaim(stakers[i].stakeId, stakeTime,stakers[i].tokenIds.length);
            if(count > 0){
                flag = true;
                break;
            }
        }
        return flag;
    }

    function printUserClaims() public  view returns (uint256[] memory, uint[] memory) {
        RecipeStaker[] memory stakers = recipeStakers[msg.sender];
        uint256[] memory stakeIds = new uint256[](stakers.length);
        uint256[] memory claims = new uint256[](stakers.length);
        for(uint256 i =0; i < stakers.length; i++ ){
            stakeIds[i] = stakers[i].stakeId;
            uint256 stakeTime =  stakers[i].time;
            claims[i] =  numberOfRewardsToClaim(stakers[i].stakeId, stakeTime,  stakers[i].tokenIds.length);
        }

        return(stakeIds, claims);
    }

    function printUserStakes() public  view returns (RecipeStaker[] memory) {
        return recipeStakers[msg.sender];
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}
}

