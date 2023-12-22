// SPDX-License-Identifier: MIT
/// @author MrD 

pragma solidity >=0.8.11;

import "./Ownable.sol";
import "./ReentrancyGuard.sol";
import "./IERC1155Receiver.sol";
import "./SafeERC20.sol";

import "./IERC20Minter.sol";
import "./ERC1155Tradable.sol";
import "./IGameCoordinator.sol";
import "./IRentShares.sol";

/**
 * @dev Contract for handling the NFT staking and set creation.
 */

contract NftStaking is  Ownable, IERC1155Receiver, ReentrancyGuard {
    using SafeERC20 for IERC20Minter;

    struct NftSet {
        uint256[] nftIds;
        uint256 tokensPerDayPerNft;      //reward per day per nft
        uint256 bonusMultiplier;    // bonus for a full set 100% bonus = 1e5
        bool isRemoved;
    }

     struct Contracts {
        ERC1155Tradable nfts;
        IERC20Minter token;
        IGameCoordinator gameCoordinator;
        IRentShares rentShares;
    }

    struct Settings {
        bool stakingActive;
        uint256 maxStake;
        uint256 riskMod;
        bool checkRoll;
        uint256 levelLimit;
        uint256 maxHarvestTime;
        uint256 powerUpBurn;
        uint256 boostBurn;
        // amount of tokens to lock per slot
        uint256 tokenPerSlot;
        // amount of free slots
        uint256 freeSlots;
        uint256 endHarvestTime;
        uint256 modBase;
    }

    // types
    // 1 = percent boost
    // 2 = perday boost
    struct FarmBoostInfo {
        uint256 boostType; // what type of boost this is 
        uint256 boostNftId; // Nft id's that relate to this boost
        uint256 boostValue;  // the value that is tied to this boost
    }

    mapping(address => bool) public hasMigrated;

    // The burn address
    address public constant burnAddress = address(0xdead);  

    //dev address 
    address public operationsAddress;

    uint256[] public nftSetList;

    //Highest NftId added to the museum
    uint256 public highestNftId;

    Contracts public contracts;
    Settings public settings;

    //Addresses that can harvest on other users behalf, ie, game contracts
    mapping(address => bool) private canAdminHarvest;

    //SetId mapped to all nft IDs in the set.
    mapping (uint256 => NftSet) public nftSets;

    //NftId to SetId mapping
    mapping (uint256 => uint256) private nftToSetMap;

    //toal staked for each nftId
    mapping (uint256 => uint256) public totalStaked;

    //user's nfts staked mapped to the nftID with the value of the idx of stakedNfts
    mapping (address => mapping(uint256 => uint256)) public userNfts;

    //Status of nfts staked mapped to the user addresses
    mapping (uint256 => mapping(uint256 => address)) public stakedNfts;

    // amount per day saved on stake/unstake to cut loops out of harvesting
    mapping (address => uint256) public currentPerDay;

    // mapping of NFT ids that are valid power ups
    mapping (uint256 => bool) public powerUps;

    //users power up nft stakes
    mapping (address => uint256) public powerUpsStaked;

    // mapping of NFT ids that are valid farm boosts
    mapping(uint256 => FarmBoostInfo) public farmBoostInfo;

    //users boost nft stakes
    mapping (address => uint256) public farmBoostStaked;
    
    // mapping of custom burn amounts for power ups and boosters
    mapping (uint256 => uint256) public customBurnFees;

    //Last update time for a user's Token rewards calculation
    mapping (address => uint256) public userLastUpdate;

    // user token locks
    mapping (address => uint256) public userLocked;

    event Stake(address indexed user, uint256[] nftIds);
    event Unstake(address indexed user, uint256[] nftIds);
    event Harvest(address indexed user, uint256 amount);
    event PowerUpStaked(address indexed user, uint256 nftId);
    event PowerUpUnstaked(address indexed user, uint256 nftId);
    event FarmBoostStaked(address indexed user, uint256 nftId);
    event FarmBoostUnstaked(address indexed user, uint256 nftId);

    constructor(
        ERC1155Tradable _nftContractAddr, 
        IERC20Minter _tokenAddr, 
        IGameCoordinator _gameCoordinator,
        IRentShares _rentShares,
        address _operationsAddress

    ) { 
        contracts.nfts = _nftContractAddr;
        contracts.token = _tokenAddr;
        contracts.gameCoordinator = _gameCoordinator;
        contracts.rentShares = _rentShares;
        operationsAddress = _operationsAddress;
        canAdminHarvest[msg.sender] = true;
    }

    /**
     * @dev Utility function to check if a value is inside an array
     */
    function _isInArray(uint256 _value, uint256[] memory _array) internal pure returns(bool) {
        uint256 length = _array.length;
        for (uint256 i = 0; i < length; ++i) {
            if (_array[i] == _value) {
                return true;
            }
        }
        return false;
    }

    event LockTokens(address indexed user, uint256 amount, uint256 maxSlots);
    function lockToken(uint256 _amount) external nonReentrant {
        require(_amount > 0 && contracts.token.balanceOf(msg.sender) >= _amount, 'not enough');

        userLocked[msg.sender] = userLocked[msg.sender] + _amount;
        // move the tokens
        contracts.token.safeTransferFrom(address(msg.sender), address(this), _amount);
        emit LockTokens(msg.sender,_amount, _getMaxSlots(msg.sender));
    }

    event UnLockTokens(address indexed user, uint256 amount, uint256 maxSlots);
    function unLockToken(uint256 _amount) external nonReentrant {
        // make sure they have enough locked and that once they withdraw it doesn't lead to more staked NFTs than slots
        require(userLocked[msg.sender] >= _amount && (((userLocked[msg.sender] - _amount)/settings.tokenPerSlot)  + settings.freeSlots >= _getNumOfNftsStakedByAddress(msg.sender)), 'unstake first');

        userLocked[msg.sender] = userLocked[msg.sender] - _amount;
        // move the tokens
        //contracts.token.safeTransferFrom(address(this), address(msg.sender), _amount);
        contracts.token.safeTransfer(address(msg.sender), _amount);
        emit UnLockTokens(msg.sender,_amount, _getMaxSlots(msg.sender));
    }

    function getMaxSlots(address _address) external view returns(uint256){
        return _getMaxSlots(_address);
    }

    function _getMaxSlots(address _address) internal view returns(uint256){
        uint256 totalSlots = (userLocked[_address]/settings.tokenPerSlot) + settings.freeSlots;

        if(totalSlots > settings.maxStake){
            return settings.maxStake;
        }

        if(totalSlots <= settings.freeSlots){
            return settings.freeSlots;
        }
        return totalSlots;
    }

    /**
     * @dev Indexed boolean for whether a nft is staked or not. Index represents the nftId.
     */
    function getNftsStakedOfAddress(address _user) public view returns(uint256[] memory) {
        uint256[] memory nftsStaked = new uint256[](highestNftId + 1);
        for (uint256 i = 0; i < highestNftId + 1; ++i) {           
            nftsStaked[i] = userNfts[_user][i];
        }
        return nftsStaked;
    }
    
    /**
     * @dev Returns the list of nftIds which are part of a set
     */
    function getNftIdListOfSet(uint256 _setId) external view returns(uint256[] memory) {
        return nftSets[_setId].nftIds;
    }
    

    /**
     * @dev returns all the addresses that have a nftId staked
     */
    function getStakersOfNft(uint256 _nftId) external view returns(address[] memory) {
        address[] memory nftStakers = new address[](totalStaked[_nftId]);

        uint256 cur;
        for (uint256 i = 1; i <= totalStaked[_nftId]; ++i) {
            if(stakedNfts[_nftId][i] != address(0)){
                nftStakers[cur] = stakedNfts[_nftId][i];
                cur += 1;
            }
        }
        return nftStakers;
    }
 
    /**
     * @dev Indexed  boolean of each setId for which a user has a full set or not.
     */
    function getFullSetsOfAddress(address _user) public view returns(bool[] memory) {
        uint256 length = nftSetList.length;
        bool[] memory isFullSet = new bool[](length);
        for (uint256 i = 0; i < length; ++i) {
            uint256 setId = nftSetList[i];
            if (nftSets[setId].isRemoved) {
                isFullSet[i] = false;
                continue;
            }
            bool _fullSet = true;
            uint256[] memory _nftIds = nftSets[setId].nftIds;
            
            for (uint256 j = 0; j < _nftIds.length; ++j) {
                if (userNfts[_user][_nftIds[j]] == 0) {
                    _fullSet = false;
                    break;
                }
            }
            isFullSet[i] = _fullSet;
        }
        return isFullSet;
    }

    /**
     * @dev Returns the amount of NFTs staked by an address for a given set
     */
    function getNumOfNftsStakedForSet(address _user, uint256 _setId) public view returns(uint256) {
        uint256 nbStaked = 0;
        if (nftSets[_setId].isRemoved) return 0;
        uint256 length = nftSets[_setId].nftIds.length;
        for (uint256 j = 0; j < length; ++j) {
            uint256 nftId = nftSets[_setId].nftIds[j];
            if (userNfts[_user][nftId] > 0) {
                nbStaked = nbStaked + 1;
            }
        }
        return nbStaked;
    }

    /**
     * @dev Returns the total amount of NFTs staked by an address across all sets
     */
    function getNumOfNftsStakedByAddress(address _user) public view returns(uint256) {
        
        return _getNumOfNftsStakedByAddress(_user);
    }

    function _getNumOfNftsStakedByAddress(address _user) internal view returns(uint256) {
        uint256 nbStaked = 0;
        for (uint256 i = 0; i < nftSetList.length; ++i) {
            nbStaked = nbStaked + getNumOfNftsStakedForSet(_user, nftSetList[i]);
        }
        return nbStaked;
    }
    
    /**
     * @dev Returns the total per day before any other adjustments or mods
     */ 
    function _calcPerDay(address _user) private view returns(uint256){
        uint256 totalTokensPerDay = 0;
        uint256 length = nftSetList.length;
        for (uint256 i = 0; i < length; ++i) {
            uint256 setId = nftSetList[i];
            NftSet storage set = nftSets[setId];
            if (set.isRemoved) continue;
            uint256 nftLength = set.nftIds.length;
            bool isFullSet = true;
            uint256 setTokensPerDay = 0;
            for (uint256 j = 0; j < nftLength; ++j) {
                if (userNfts[_user][set.nftIds[j]] == 0) {
                    isFullSet = false;
                    continue;
                }
                setTokensPerDay = setTokensPerDay + set.tokensPerDayPerNft;
            }
            if (isFullSet) {
                setTokensPerDay = (setTokensPerDay * set.bonusMultiplier)/1e5;
            }
            totalTokensPerDay = totalTokensPerDay + setTokensPerDay;
        }
        return totalTokensPerDay;
    }

    /**
     * @dev Returns the total tokens pending for a given address. will return the totalPerDay,
     * if second param is set to true.
     */
    function totalPendingTokensOfAddress(address _user, bool _perDay) public view returns (uint256) {

        uint256 totalTokensPerDay = currentPerDay[_user];
        totalTokensPerDay = (totalTokensPerDay * settings.riskMod) / 1 ether;

        
        
        uint256 lastUpdate = userLastUpdate[_user];
       // uint256 lastRollTime = contracts.gameCoordinator.getLastRollTime(_user);
        uint256 blockTime = block.timestamp;
        uint256 maxTime = lastUpdate + settings.maxHarvestTime;

        if(settings.maxHarvestTime > 0){

            // if we are checking the roll, set the max time to the last roll instead of last harvest
            // if(settings.checkRoll ){
            //     maxTime = lastRollTime + settings.maxHarvestTime;
            // }

            if( maxTime < blockTime){
                blockTime = maxTime;
            }            
        }

        if(settings.endHarvestTime > 0){
            if( settings.endHarvestTime  < blockTime){
                blockTime = settings.endHarvestTime;
            }
        }

        uint256 playerLevel = contracts.gameCoordinator.getLevel(_user);
        uint256 yieldMod = playerLevel + settings.modBase;

        totalTokensPerDay = (totalTokensPerDay * yieldMod) / 100;

        // check for farm boosts
        if(farmBoostStaked[_user] > 0){
            if(farmBoostInfo[farmBoostStaked[_user]].boostType == 1){
               // adjust based on a multiplier
               uint256 boostedValue = totalTokensPerDay * farmBoostInfo[farmBoostStaked[_user]].boostValue;
               totalTokensPerDay = boostedValue / 1 ether;
            }

            if(farmBoostInfo[farmBoostStaked[_user]].boostType == 2){
                // direct adjustment
                totalTokensPerDay = totalTokensPerDay + farmBoostInfo[farmBoostStaked[_user]].boostValue;
            }
        }

        if(_perDay || totalTokensPerDay == 0){
            return totalTokensPerDay;
        }

        return (blockTime - lastUpdate) * (totalTokensPerDay/86400);
    }

    function getYieldMod(address _user) public view returns(uint256){
        uint256 playerLevel = contracts.gameCoordinator.getLevel(_user);
        //uint256 levelMod = playerLevel.div(10).mul(1 ether);
        uint256 levelMod = (playerLevel * 1 ether)/10;
        if(levelMod <= 0){
            levelMod = 1 ether;
        }

        return playerLevel + settings.modBase;
    }


    /**
     * @dev Manually sets the highestNftId, if it goes out of sync.
     * Required calculate the range for iterating the list of staked nfts for an address.
     */
    function setHighestNftId(uint256 _highestId) external onlyOwner {
        // require(_highestId > 0, "Set if minimum 1 nft is staked.");
        highestNftId = _highestId;
    }

    /**
     * @dev Adds a nft set with the input param configs. Removes an existing set if the id exists.
     */
     // bool _isBooster,
     // uint256 _bonusFullSetBoost
     // uint256[] memory _poolBoosts, 
    event SetAdded(uint256 setId, uint256 setBonus, uint256 perDay, uint256[] nftIds);
    function addNftSet(
        uint256 _setId, 
        uint256[] calldata _nftIds, 
        uint256 _bonusMultiplier, 
        uint256 _tokensPerDayPerNft
        
        ) external onlyOwner {
            removeNftSet(_setId);
            uint256 length = _nftIds.length;
            for (uint256 i = 0; i < length; ++i) {
                uint256 nftId = _nftIds[i];
                if (nftId > highestNftId) {
                    highestNftId = nftId;
                }
                // Check all nfts to assign arent already part of another set
                require(nftToSetMap[nftId] == 0, "Nft already assigned to a set");
                // Assign to set
                nftToSetMap[nftId] = _setId;
            }
            if (_isInArray(_setId, nftSetList) == false) {
                nftSetList.push(_setId);
            }
            nftSets[_setId] = NftSet({
                nftIds: _nftIds,
                bonusMultiplier: _bonusMultiplier,
                tokensPerDayPerNft: _tokensPerDayPerNft,
                isRemoved: false
            });

            emit SetAdded(_setId,_bonusMultiplier,_tokensPerDayPerNft,_nftIds);
    }


    /**
     * @dev Remove a nftSet that has been added.
     */
    function removeNftSet(uint256 _setId) public onlyOwner {
        uint256 length = nftSets[_setId].nftIds.length;
        for (uint256 i = 0; i < length; ++i) {
            uint256 nftId = nftSets[_setId].nftIds[i];
            nftToSetMap[nftId] = 0;
        }
        delete nftSets[_setId].nftIds;
        nftSets[_setId].isRemoved = true;
    }

    /**
     * @dev Public harvest function
     */
    function harvest() public nonReentrant {
        _harvest(msg.sender);
    }

    /**
     * @dev Allow owner to call harvest for an account
     */
    function gameHarvest(address _user) public {
        require(canAdminHarvest[msg.sender],'Nope');
        _harvest(_user);
    }

    function gameSetLastUpdate(address _user, uint256 lastUpdate) public {
        require(canAdminHarvest[msg.sender],'Nope');
        userLastUpdate[_user] = lastUpdate;
    }

    /**
     * @dev Harvests the accumulated Token in the contract, for the caller.
     */
    function _harvest(address _user) private {
        // require(!checkRoll || memenopoly.playerActive(msg.sender) ,"You must take a roll to harvest");
        require(canAdminHarvest[msg.sender] || _isActive(_user), "NftStaking: Farms locked");
        uint256 pendingTokens = totalPendingTokensOfAddress(_user,false);
        userLastUpdate[_user] = block.timestamp;
        if (pendingTokens > 0) {
            contracts.token.mint(operationsAddress, pendingTokens / 40); // 2.5% Token for the dev 
            contracts.token.mint(_user, pendingTokens);
        }
        emit Harvest(_user, pendingTokens);
    }

    /**
     * @dev Stakes the nfts on providing the nft IDs. 
     */
    function stake(uint256[] calldata _nftIds) external nonReentrant {
        /*require(_nftIds.length > 0, "you need to stake something");
        require(_isActive(msg.sender), "NftStaking: Farms locked");
        require(settings.maxStake == 0 || _getNumOfNftsStakedByAddress(msg.sender) + _nftIds.length <= _getMaxSlots(msg.sender), 'Max nfts staked');*/
        require(_nftIds.length > 0 && isActive(msg.sender) && (settings.maxStake == 0 || _getNumOfNftsStakedByAddress(msg.sender) + _nftIds.length <= _getMaxSlots(msg.sender)), "Can't Stake");
        // require(!checkRoll || memenopoly.playerActive(msg.sender) ,"You must take a roll to stake");
        // Check no nft will end up above max stake and if it is needed to update the user NFT pool

        _harvest(msg.sender);


        uint256 length = _nftIds.length;

        for (uint256 i = 0; i < length; ++i) {
            uint256 nftId = _nftIds[i];
            // require(userNfts[msg.sender][nftId] == 0, "item already staked");
            require(nftToSetMap[nftId] != 0 && userNfts[msg.sender][nftId] == 0, "you can't stake that");
        }
        
        //Stake 1 unit of each nftId
        uint256[] memory amounts = new uint256[](_nftIds.length);
        for (uint256 i = 0; i < _nftIds.length; ++i) {
            amounts[i] = 1;
        }

        contracts.rentShares.batchGiveShares(msg.sender, _nftIds);
        contracts.nfts.safeBatchTransferFrom(msg.sender, address(this), _nftIds, amounts, "");
        //Update the staked status for the nft ID.
        for (uint256 i = 0; i < length; ++i) {
            uint256 nftId = _nftIds[i];
            totalStaked[nftId] = totalStaked[nftId] + 1;

            userNfts[msg.sender][nftId] = totalStaked[nftId]; 
            stakedNfts[nftId][totalStaked[nftId]] = msg.sender;
            
        }

        // update the currentPerDay
        currentPerDay[msg.sender] =  _calcPerDay(msg.sender);

        emit Stake(msg.sender, _nftIds);


    }
  
     /**
     * @dev Unstakes the nfts on providing the nft IDs. 
     */
    function unstake(uint256[] calldata _nftIds) external nonReentrant {
 
         // require(_nftIds.length > 0, "input at least 1 nft id");
         require(_nftIds.length > 0 && _isActive(msg.sender), "NftStaking: Farms locked");
         // require(!checkRoll || memenopoly.playerActive(msg.sender) ,"You must take a roll to unstake");

         _harvest(msg.sender);

        // Check if all nfts are staked and if it is needed to update the user NFT pool
        uint256 length = _nftIds.length;

        for (uint256 i = 0; i < length; ++i) {
            uint256 nftId = _nftIds[i];
            require(userNfts[msg.sender][nftId] > 0, "Nft not staked");

            // move the last item to the idx we just deleted
            if(userNfts[msg.sender][nftId] != totalStaked[nftId]){
                stakedNfts[nftId][userNfts[msg.sender][nftId]] = stakedNfts[nftId][totalStaked[nftId]];
                userNfts[stakedNfts[nftId][totalStaked[nftId]]][nftId] = userNfts[msg.sender][nftId];
            } 
            
            delete stakedNfts[nftId][totalStaked[nftId]];
            userNfts[msg.sender][nftId] = 0;
            
            totalStaked[nftId] = totalStaked[nftId] - 1 ;

        }
        
        contracts.rentShares.batchRemoveShares(msg.sender, _nftIds);

        //Unstake 1 unit of each nftId
        uint256[] memory amounts = new uint256[](_nftIds.length);
        for (uint256 i = 0; i < _nftIds.length; ++i) {
            amounts[i] = 1;
        }

        // update the currentPerDay
        currentPerDay[msg.sender] =  _calcPerDay(msg.sender);
        contracts.nfts.safeBatchTransferFrom(address(this), msg.sender, _nftIds, amounts, "");

        emit Unstake(msg.sender, _nftIds);
    }

    /**
     * @dev Emergency unstake the nfts on providing the nft IDs, forfeiting the Token rewards 
     */
    function emergencyUnstake(uint256[] calldata _nftIds) external nonReentrant {

        userLastUpdate[msg.sender] = block.timestamp;
        uint256 length = _nftIds.length;

        for (uint256 i = 0; i < length; ++i) {
            uint256 nftId = _nftIds[i];
            require(userNfts[msg.sender][nftId] > 0, "Nft not staked");
            // move the last item to the idx we just deleted
            if(userNfts[msg.sender][nftId] != totalStaked[nftId]){
                stakedNfts[nftId][userNfts[msg.sender][nftId]] = stakedNfts[nftId][totalStaked[nftId]];
                userNfts[stakedNfts[nftId][totalStaked[nftId]]][nftId] = userNfts[msg.sender][nftId];
            } 


            delete stakedNfts[nftId][totalStaked[nftId]];
            userNfts[msg.sender][nftId] = 0;
            
            totalStaked[nftId] = totalStaked[nftId] - 1;

        }
        
        contracts.rentShares.batchRemoveShares(msg.sender, _nftIds);

        //Unstake 1 unit of each nftId
        uint256[] memory amounts = new uint256[](_nftIds.length);
        for (uint256 i = 0; i < _nftIds.length; ++i) {
            amounts[i] = 1;
        }
        
        // update the currentPerDay
        currentPerDay[msg.sender] =  _calcPerDay(msg.sender);
        contracts.nfts.safeBatchTransferFrom(address(this), msg.sender, _nftIds, amounts, "");

    }
    
    function isActive(address _address) public view returns(bool){
        return _isActive(_address);
    }

    function _isActive(address _address) private view returns(bool){
        uint256 playerLevel = contracts.gameCoordinator.getLevel(_address);

        if(settings.stakingActive && (!settings.checkRoll || contracts.gameCoordinator.playerActive(msg.sender)) && playerLevel >= settings.levelLimit){ // && playerTier >= tierLimit
            return true;
        }
        return false;

    }
    
    event CustomBurnFeeSet(uint256 nftId, uint256 amount);
    function setCustomBurnFee(uint256 _nftId, uint256 _amount) public onlyOwner {
        customBurnFees[_nftId] = _amount;
        emit CustomBurnFeeSet(_nftId, _amount);
    }

    event FarmBoostSet(uint256 nftId, uint256 boostType, uint256 boostValue);
    function setFarmBoost(uint256 _boostNftId, uint256 _boostType, uint256 _boostValue) public onlyOwner {
        farmBoostInfo[_boostNftId].boostNftId = _boostNftId;
        farmBoostInfo[_boostNftId].boostType = _boostType;
        farmBoostInfo[_boostNftId].boostValue = _boostValue;
        emit FarmBoostSet(_boostNftId, _boostType, _boostValue);
    }

    /**
     * @dev Stakes the farm boost
     */
    function stakeFarmBoost(uint256 _nftId) external {
        require(farmBoostInfo[_nftId].boostNftId == _nftId && farmBoostStaked[msg.sender] != _nftId, "Can't Stake Booster");
        require(_isActive(msg.sender), "Farms Locked");

        if(settings.boostBurn > 0 || customBurnFees[_nftId] > 0){
            bool burnSuccess = false;
            uint256 burnFee = settings.boostBurn;

            if(customBurnFees[_nftId] > 0){
                burnFee = customBurnFees[_nftId];
            }
            require(contracts.token.balanceOf(msg.sender) >= burnFee, 'Not enough to burn');

            burnSuccess = contracts.token.transferFrom(msg.sender, burnAddress, burnFee);
            require(burnSuccess, "Burn failed");
        }
        _harvest(msg.sender);

        // unstake a boost if it's already staked
        if(farmBoostStaked[msg.sender] > 0){
            _unStakeFarmBoost();
        }

        // transfer it to the contract
        contracts.nfts.safeTransferFrom(msg.sender, address(this), _nftId, 1, "");
        farmBoostStaked[msg.sender] = _nftId;

        emit FarmBoostStaked(msg.sender, _nftId);
    }

    /**
     * @dev Unstake a powerup nft if there is one for this addres 
     */
    function unStakeFarmBoost() public {
        _harvest(msg.sender);
        _unStakeFarmBoost();
    }

    function _unStakeFarmBoost() private {
        require(farmBoostStaked[msg.sender] > 0, "nftStaking: No Booster Staked");
        require(_isActive(msg.sender), "Farms Locked");
        
        uint256 nftId = farmBoostStaked[msg.sender];
        farmBoostStaked[msg.sender] = 0;
        // transfer from the contract back to the owner
        contracts.nfts.safeTransferFrom(address(this), msg.sender,  nftId, 1, "");
        

        emit FarmBoostUnstaked(msg.sender, nftId);
    }

    /**
     * @dev Simple way to get the boost in other contracts
     */
    function getFarmBoost(address _address) external view returns(uint256) {
        return farmBoostStaked[_address];
    }

    function addPowerUp(uint256 _nftId) external onlyOwner {
        powerUps[_nftId] = true;
    }

    function removePowerUp(uint256 _nftId) external onlyOwner {
        powerUps[_nftId] = false;
    }

    /**
     * @dev Stakes a PowerUp NFT 
     */
    function stakePowerUp(uint256 _nftId) external {
        require(powerUps[_nftId] && powerUpsStaked[msg.sender] != _nftId, "Can't Stake PowerUp");
        // require(powerUpsStaked[msg.sender] != _nftId, "NftStaking: Power up already staked");

        if(settings.powerUpBurn > 0 || customBurnFees[_nftId] > 0){
            bool burnSuccess = false;

            uint256 burnFee = settings.powerUpBurn;

            if(customBurnFees[_nftId] > 0){
                burnFee = customBurnFees[_nftId];
            }

            require(contracts.token.balanceOf(msg.sender) >= burnFee, 'Not enough to burn');

            burnSuccess = contracts.token.transferFrom(msg.sender, burnAddress, burnFee);
            require(burnSuccess, "Burn failed");
        }

        // unstake a powerup if it's already staked
        if(powerUpsStaked[msg.sender] > 0){
            unStakePowerUp();
        }

        // transfer it to the contract
        contracts.nfts.safeTransferFrom(msg.sender, address(this), _nftId, 1, "");
        powerUpsStaked[msg.sender] = _nftId;

        emit PowerUpStaked(msg.sender, _nftId);
    }

    /**
     * @dev Unstake a powerup nft if there is one for this addres 
     */
    function unStakePowerUp() public {
        require(powerUpsStaked[msg.sender] > 0, "NftStaking: No Powerup Staked");

        uint256 nftId = powerUpsStaked[msg.sender];
        powerUpsStaked[msg.sender] = 0;
        // transfer from the contract back to the owner
        contracts.nfts.safeTransferFrom(address(this), msg.sender,  nftId, 1, "");
        

        emit PowerUpUnstaked(msg.sender, nftId);
    }

    /**
     * @dev Simple way to get the powerup from the game
     */
    function getPowerUp(address _address) external view returns(uint256) {
        return powerUpsStaked[_address];
    }


    /**
     * @dev set the contract addresses
     */
    function setContracts(
        IERC20Minter _tokenAddr, 
        ERC1155Tradable _nft, 
        IGameCoordinator _gameCoordinator,
        IRentShares _rentShares
    ) external onlyOwner {
        contracts.token = _tokenAddr;
        contracts.nfts = _nft;
        contracts.gameCoordinator = _gameCoordinator;
        contracts.rentShares = _rentShares;
    }  

    function setOperationsAddress(address _operationsAddress) public onlyOwner {
        operationsAddress = _operationsAddress;
    }

    function addAdminHarvestAddress(address _address) public onlyOwner {
        canAdminHarvest[_address] = true;
    }

    function removeAdminHarvestAddress(address _address) public onlyOwner {
        canAdminHarvest[_address] = false;
    }

    function updateSettings(
        bool _stakingActive,
        bool _checkRoll,
        uint256 _riskMod,
        uint256 _maxHarvestTime,
        uint256 _maxStake,
        uint256 _powerUpBurn,
        uint256 _boostBurn,
        uint256 _levelLimit,
        uint256 _tokenPerSlot,
        uint256 _freeSlots,
        uint256 _endHarvestTime,
        uint256 _modBase

    ) public onlyOwner{
        settings.stakingActive = _stakingActive;
        settings.checkRoll = _checkRoll;
        settings.riskMod = _riskMod;
        settings.maxHarvestTime = _maxHarvestTime;
        settings.maxStake = _maxStake;
        settings.powerUpBurn = _powerUpBurn;
        settings.boostBurn = _boostBurn;
        settings.levelLimit = _levelLimit;
        settings.tokenPerSlot = _tokenPerSlot;
        settings.freeSlots = _freeSlots;
        settings.endHarvestTime = _endHarvestTime;
        settings.modBase = _modBase;
    }



    function onERC1155Received(address, address, uint256, uint256, bytes calldata) external pure override returns(bytes4) {
      return 0xf23a6e61;
    }

    function onERC1155BatchReceived(address, address, uint256[] calldata, uint256[] calldata, bytes calldata) external pure override returns(bytes4) {
      return 0xbc197c81;
    }

    function supportsInterface(bytes4 interfaceID) public view virtual override returns (bool) {
      return  interfaceID == 0x01ffc9a7 ||    // ERC-165 support (i.e. `bytes4(keccak256('supportsInterface(bytes4)'))`).
      interfaceID == 0x4e2312e0;      // ERC-1155 `ERC1155TokenReceiver` support (i.e. `bytes4(keccak256("onERC1155Received(address,address,uint256,uint256,bytes)")) ^ bytes4(keccak256("onERC1155BatchReceived(address,address,uint256[],uint256[],bytes)"))`).
  }
}
