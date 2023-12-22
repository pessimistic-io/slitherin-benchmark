// SPDX-License-Identifier: MIT

pragma solidity >=0.8.9 <0.9.0;

import "./IERC721Upgradeable.sol";
import "./ERC721HolderUpgradeable.sol";
import "./ERC1155HolderUpgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";
import "./Initializable.sol";
import "./UUPSUpgradeable.sol";

interface IIngredientERC1155{
    function safeTransferFrom(address from, address to, uint id, uint amount, bytes memory data) external;
    function burn(address account, uint256 id, uint256 value) external;
    function burnBatch(address account, uint256[] memory ids, uint256[] memory values) external;
}

interface IGen1ERC1155{
    function mint(address account, uint256 id, uint256 amount) external;
}

interface IPancakeERC1155{
    function mint(address account, uint256 id, uint256 amount) external;
}

interface IBossCardERC1155{
    function safeTransferFrom(address from, address to, uint id, uint amount, bytes memory data) external;
}
interface ISignatureChecker {
   function checkSignature(bytes32 signedHash, bytes memory signature) external returns(bool);
}

interface IShrineConst {
    function revealGen1NftId() external returns(uint256);
    function revealPancakeIdNftId() external returns(uint256);
    function  revealNumber(uint from, uint to) external returns(uint);
    function revealSuccessNumber() external returns(uint256);
}


contract Shrine is Initializable, ERC721HolderUpgradeable,OwnableUpgradeable, ReentrancyGuardUpgradeable, UUPSUpgradeable {
    uint private ceilSuccessNo;
    uint256 public timeForReward;

    // for stake
    IERC721Upgradeable private powerPlinsGen0;
    address ingredientsERC1155;
    address bossCardERC1155;

    //for reward
    address gen1ERC1155;
    address pancakeERC1155;

    IShrineConst shrineConst;
    address signatureChecker;

    //recipe info
    struct RecipeStake{
        uint tokenId;
        uint time;
        uint boostValue;
    }
    mapping(address => RecipeStake) private recipeStake;

    struct IngredientStake{
        uint[] tokenIds;
        uint[] amounts;
        uint stakeTime;
    }
    mapping(address => IngredientStake) private IngredientStakes;


    uint[] cooldownBoost;

    struct BossCardStake{
        uint tokenId;
        string traitType;
        uint value;
    }
    mapping(address => BossCardStake) private bossCardStakes;

    uint[] private common;
    uint[] private uncommon;
    uint[] private rare;
    uint[] private epic;
    uint[] private legendary;

    function initialize(address _powerPlinsGen0, address _ingredientsERC1155, address _bossCardERC1155, address _gen1ERC1155, address _pancakeERC1155, address _shrineConst, address _signatureChecker) external initializer {
        __ERC721Holder_init();
        __Ownable_init();
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();
        //__ERC1155Holder_init();
        ceilSuccessNo = 10000;
        timeForReward = 24 hours;
        powerPlinsGen0 = IERC721Upgradeable(_powerPlinsGen0);
        ingredientsERC1155 = _ingredientsERC1155;
        bossCardERC1155 = _bossCardERC1155;
        gen1ERC1155 = _gen1ERC1155;
        pancakeERC1155 = _pancakeERC1155;
        shrineConst = IShrineConst(_shrineConst);
        signatureChecker=_signatureChecker;
        cooldownBoost = [37,63,97,38,94,98];
        common = [1,2,3,4,5];
        uncommon = [6,7,8];
        rare = [9,10,11,12,13,14,15,16,17,18,19];
        epic = [20,21,22,23,24];
        legendary = [25];
    }
    function indexOf(uint[] storage self, uint value) private view returns (int) {
        for (uint i = 0; i < self.length; i++)if (self[i] == value) return int(i);
        return -1;
    }
    function onERC1155Received(address, address, uint256, uint256, bytes memory) public virtual returns (bytes4) {
        return this.onERC1155Received.selector;
    }

    function compareStrings(string memory a, string memory b) internal pure returns (bool) {
        return keccak256(abi.encodePacked(a)) == keccak256(abi.encodePacked(b));
    }

    function setTimeForReward(uint256 _timeForReward) external {
        timeForReward = _timeForReward;
    }

    function stakeRecipe(uint _tokenId, uint _boostValue, bytes calldata _signature) external {
        require(_tokenId >= 0, "Staking: No tokenIds provided");
        bytes32 message = keccak256(abi.encodePacked(msg.sender,_tokenId,_boostValue));
        bool isSender = ISignatureChecker(signatureChecker).checkSignature(message, _signature);
        require(isSender, "Invalid sender");
        powerPlinsGen0.safeTransferFrom(msg.sender, address(this), _tokenId);
        recipeStake[msg.sender].tokenId = _tokenId;
        recipeStake[msg.sender].boostValue = _boostValue;
        recipeStake[msg.sender].time = block.timestamp;
        emit Staked(msg.sender, _tokenId);
    }

    function unStakeRecipe(uint _tokenId) external nonReentrant {
        require(_tokenId >= 0, "unStack: No tokenId found");
        require(recipeStake[msg.sender].tokenId >= 0, "unStack: No tokenId found");
        require(!anyClaimInProgress(),"Reward in progress");

        powerPlinsGen0.safeTransferFrom(address(this), msg.sender, _tokenId);
        delete recipeStake[msg.sender];
        emit UnStaked(msg.sender, _tokenId);
    }

    function stakeIngredients(uint[] memory _tokenIds, uint[] memory _amounts) external {
        require(recipeStake[msg.sender].tokenId > 0, "stake: First stake recipe Nft!");
        require(_tokenIds.length == _amounts.length, "stake: length mismatch");
        uint countAmount = 0;
        for(uint i=0; i < _amounts.length; i++){
            countAmount = countAmount + _amounts[i];
        }
        require(countAmount >= 5 && countAmount <= 100, "stake: minimum 5 and maximum 100 can stake");
        for(uint i=0; i < _tokenIds.length; i++){
            IIngredientERC1155(ingredientsERC1155).safeTransferFrom(msg.sender, address(this), _tokenIds[i], _amounts[i],'');
        }
        IngredientStakes[msg.sender].tokenIds = _tokenIds;
        IngredientStakes[msg.sender].amounts = _amounts;
        IngredientStakes[msg.sender].stakeTime = block.timestamp;
    }

    function bossCardStake(uint _tokenId, string memory _traitType, uint _value, bytes calldata _signature) external {
        require(
            bossCardStakes[msg.sender].tokenId ==0,
            "Boost token already stake"
        );
        bytes32 message = keccak256(abi.encodePacked(msg.sender,_tokenId,_traitType,_value));
        bool isSender = ISignatureChecker(signatureChecker).checkSignature(message, _signature);
        require(isSender, "Invalid sender");
        bossCardStakes[msg.sender].tokenId =_tokenId;
        bossCardStakes[msg.sender].traitType =_traitType;
        bossCardStakes[msg.sender].value =_value;
        IBossCardERC1155(bossCardERC1155).safeTransferFrom(msg.sender, address(this), _tokenId, 1,'');
    }

    function unStakeBoostCard(uint _tokenId) external nonReentrant{
        require(
            !anyClaimInProgress(),
            "Claim in progress"
        );
        IBossCardERC1155(bossCardERC1155).safeTransferFrom(address(this), msg.sender,_tokenId, 1,'');
        delete bossCardStakes[msg.sender];
    }

    function canAvailableClaim(uint256 _stakeTime) internal  view returns (bool) {
        if(_stakeTime == 0){
            return false;
        }
        uint256 stakedTime = _stakeTime + getTimeForReward();
        return block.timestamp > stakedTime;
    }

    function anyClaimInProgress() public view returns(bool){
        bool flag = false;
        uint256[] memory stakeIds = IngredientStakes[msg.sender].tokenIds;
        uint stakedTime = IngredientStakes[msg.sender].stakeTime;
        for(uint256 i=0; i < stakeIds.length; i++ ){
            if(canAvailableClaim(stakedTime)){
                flag = true;
                break;
            }
        }
        return flag;
    }

    function getBoostValue(uint _mulValue, string memory _mulName) internal view returns(uint){
        string memory boostType =  bossCardStakes[msg.sender].traitType;
        if( bossCardStakes[msg.sender].tokenId == 0  || !compareStrings(boostType,_mulName)){
            return _mulValue;
        }
        uint value = bossCardStakes[msg.sender].value;
        return (_mulValue + value);
    }

    function prepareNumber( uint[] memory ids,uint[] memory amounts ) internal view returns(uint){
        if(ids.length==0){
            return 0;
        }
        uint commonIng =0;
        uint uncommonIng= 0;
        uint rareIng = 0;
        uint epicIng =0;
        uint legendaryIng = 0;
        //console.log("step1");
        for(uint i=0;i<ids.length;i++){
            if(indexOf(common,ids[i]) >=0){
                commonIng += 1*amounts[i];
            }
            else if(indexOf(uncommon,ids[i]) >=0){
                uncommonIng += 1*amounts[i];
            }
            else if(indexOf(rare,ids[i]) >=0 ){
                rareIng += 1*amounts[i];
            }
            else if(indexOf(epic,ids[i]) >=0){
                epicIng += 1*amounts[i];
            }
            else if(indexOf(legendary,ids[i]) >=0){
                legendaryIng += 1*amounts[i];
            }
        }
        uint number = 0;
        if(recipeStake[msg.sender].tokenId > 0){
            number += recipeStake[msg.sender].boostValue;
        }
        string memory boostType =  bossCardStakes[msg.sender].traitType;
        if( bossCardStakes[msg.sender].tokenId != 0  && compareStrings(boostType,"additive")){
            number += bossCardStakes[msg.sender].value;
        }
        number = (number * 100) + (number * ((commonIng*getBoostValue(2,"common")) + (uncommonIng*getBoostValue(5,"uncommon")) + (rareIng*getBoostValue(12,"rare")) + (epicIng*getBoostValue(30,"epic")) + (legendaryIng*getBoostValue(120,"legendary"))));
        return number;
    }

    function getClaimSuccessNumber() internal view returns(uint){
        return prepareNumber(IngredientStakes[msg.sender].tokenIds, IngredientStakes[msg.sender].amounts);
    }
    //Claim rewards for IngredientsERC1155

    function claimRewards(bytes calldata _signature) external{
        uint256[] memory tokenIds = IngredientStakes[msg.sender].tokenIds;
        uint256[] memory amounts = IngredientStakes[msg.sender].amounts;
        uint256 stakeTime = IngredientStakes[msg.sender].stakeTime;

        require(tokenIds.length != 0, "claimReward: No claimReward found");
        bytes32 message = keccak256(abi.encodePacked(msg.sender));
        bool isSender = ISignatureChecker(signatureChecker).checkSignature(message, _signature);
        require(isSender, "claimReward: Invalid sender");
        require(canAvailableClaim(stakeTime), "claimReward: stake not available for claim");

        uint successNo = getClaimSuccessNumber();
        uint generateNumber = shrineConst.revealSuccessNumber();
        bool isChanceFail = generateNumber > successNo;
        uint pancakeClaimId = 19;
        uint gen1ClaimId = 0;

        if(isChanceFail){
            IPancakeERC1155(pancakeERC1155).mint(msg.sender, pancakeClaimId, 1);
        }else{
            gen1ClaimId = shrineConst.revealGen1NftId();
            pancakeClaimId = shrineConst.revealPancakeIdNftId();
            IGen1ERC1155(gen1ERC1155).mint(msg.sender, gen1ClaimId, 1);
            IPancakeERC1155(pancakeERC1155).mint(msg.sender, pancakeClaimId, 1);
        }

        IIngredientERC1155(ingredientsERC1155).burnBatch(address(this), tokenIds, amounts);
        delete IngredientStakes[msg.sender];
        emit RewardClaimed(msg.sender, generateNumber, successNo, pancakeClaimId, gen1ClaimId);
    }

    function getTimeForReward() public view returns(uint256){
        if(indexOf(cooldownBoost,bossCardStakes[msg.sender].tokenId) >=0){
            uint time = bossCardStakes[msg.sender].value;
            return timeForReward - time;
        }
        return timeForReward;
    }

    function getClaimSuccessNumber(uint[] memory ids,uint[] memory amounts) external view returns(uint){
        return prepareNumber(ids, amounts);
    }

    function printUserIngredientStakes() external view returns(IngredientStake memory) {
        return IngredientStakes[msg.sender];
    }

    function printUserRecipeStake() external view returns(RecipeStake memory) {
        return recipeStake[msg.sender];
    }

    function printUserBossCardStake() external view returns(BossCardStake memory) {
        return bossCardStakes[msg.sender];
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}

    event Staked(address indexed user, uint256 tokenId);
    event UnStaked(address indexed user, uint256 tokenId);
    event RewardClaimed(
        address indexed user,
        uint randomId,
        uint successNumber,
        uint pancakeClaimId,
        uint gen1ClaimId
    );
}
