// SPDX-License-Identifier: MIT
/// @author MrD 

pragma solidity >=0.8.11;

import "./Ownable.sol";
import "./ReentrancyGuard.sol";
import "./IERC1155Receiver.sol";
import "./ERC1155Tradable.sol";

import "./IVault.sol";
import "./IGameCoordinator.sol";
import "./INftStaking.sol";

contract NftRewards is Ownable, IERC1155Receiver, ReentrancyGuard {

    // nft contract
    ERC1155Tradable public nft;

    // vault contract
    IVaultMiner public vaultMiner;

    // GameCoordinator contract
    IGameCoordinator public game;

    // Nft Staking contract
    INftStaking public nftStaking;

    // struct to hold the tier info 
    struct UserTier {
        uint256 currentTier;   // current farm tier
        uint256 tierRewards;   // the amount of farm tier points earned
    }
/*
    struct UserSubTier {
        bool unlocked;   // if the user has unlocked this sub-tier
      //  uint256[] nftIds;   // which ids this user has claimed
    }
*/
    struct TierInfo {
        uint256 tier; 
        uint256[] nftIds; 
        uint256 totalClaimed;// total redeemed 
    }

    struct SubTierInfo {
        uint256 unlockCost; // how many reward points to burn to unlock
        uint256[][] nftIds; // nftIds[subLevel][nftId]
        uint256[] nftCosts; // point cost of each nft level for this sub-tier
        uint256[] levelLimit; // required game level to claim this sub level 
        uint256[] vaultPercent; // what percent of vault shares you must own to claim this sub level ( 100 is 1%)
        uint256[] slotsUnlocked; // required amount of nft staking slots unlocked to claim this sub level
        uint256 totalClaimed;// total redeemed 
    }

    bool public isActive;
    // Migration vars 
    bool public migrationActive = true;
    mapping(address => bool) public hasMigrated;

    // mapping of which users have claimed a tier NFT
    mapping(address => mapping(uint256 => uint256)) public claimedTiers;  

    // mapping of user claimed sub tiers
    mapping(address => mapping(uint256 => bool)) public unlockedSubTiers;   
    mapping(address => mapping(uint256 => mapping(uint256 => uint256))) public claimedSubTierNfts;  

    // mapping of addresses allowed to add or remove points
    mapping(address => bool) internal isAllowed;

    // Array of the tier thresholds 
    uint256[] public tiersThresh;
    uint256 public maxTiers;
    mapping(address => UserTier) public userTier;


    // mapping the nft options for the tiers and sub-tiers
    mapping(uint256 => TierInfo) public rewardTiers;
    mapping(uint256 => SubTierInfo) public subTiers;

    uint256 public totalNftsClaimed;

    event TierRewardClaimed(address indexed user, uint256 tier, uint256 nftId);
    event SubTierRewardClaimed(address indexed user, uint256 subTier, uint256 subLevel, uint256 nftId, uint256 pointsBurned);

    event SetTierNfts(address indexed user, uint256 tier, uint256[]  nftIds);
    event SetSubTierNfts(address indexed user, uint256 subTier, uint256 subLevel, uint256[]  nftIds);
    event SubTierUnlocked(address indexed user, uint256 subTier, uint256 pointsBurned);
    event PointsAdded(address indexed user, uint256 amount);
    event PointsRemoved(address indexed user, uint256 amount);
    event TierReached(address indexed user, uint256 tier);

    constructor(
        ERC1155Tradable _nftAddress, 
        uint256[] memory _tierThresh,
        IVaultMiner _vaultMiner
    ) {

        nft = _nftAddress;
        vaultMiner = _vaultMiner;
         // set the tier thresholds
        setTierThresh(_tierThresh);
    }

    // modifier for functions only the team can call
    modifier onlyAllowed() {
        require(isAllowed[msg.sender], "Caller not in Allowed");
        _;
    }

    

    function claimTierReward(uint256 _tier,uint256 _nftId) public nonReentrant {
        require(isActive,'Not Active');

        // see if they already claimed this tier
        require(claimedTiers[msg.sender][_tier] <= 0, "Tier already claimed");
        
        // make sure the nft id is valid for that tier
        require(_isInArray(_nftId,rewardTiers[_tier].nftIds),"claim nft invalid" );

        // make sure they are at the proper tier
        require(userTier[msg.sender].currentTier >= _tier, "Tier too low");

        uint256 maxSupply = nft.tokenMaxSupply(_nftId);
        uint256 curSupply = nft.tokenSupply(_nftId);
        
        require(nft.balanceOf(address(this),_nftId) > 0 || (curSupply < maxSupply), 'Out of Stock');

        // update stats
        totalNftsClaimed = totalNftsClaimed + 1;
        rewardTiers[_tier].totalClaimed = rewardTiers[_tier].totalClaimed + 1;
        claimedTiers[msg.sender][_tier] = _nftId;

        if(nft.balanceOf(address(this),_nftId) > 0){
            nft.safeTransferFrom(address(this), msg.sender, _nftId, 1, "0x0");
        } else {
            nft.mint(msg.sender, _nftId, 1, "0x0");
        }

        // send the NFT
        // nft.mint(_nftId, 1, "0x0");
        
        emit TierRewardClaimed(msg.sender, _tier, _nftId);
        
    }

    function unlockSubTier(uint256 _subTier) public nonReentrant {
        require(!unlockedSubTiers[msg.sender][_subTier],'Sub Tier Un-Locked');

        require(_getSpendablePoints(msg.sender) >= subTiers[_subTier].unlockCost,'Not Enough Points');

        // burn the reward points
        _removePoints(msg.sender, subTiers[_subTier].unlockCost);
        unlockedSubTiers[msg.sender][_subTier] = true;

        emit SubTierUnlocked(msg.sender, _subTier,subTiers[_subTier].unlockCost);
    }

    function claimSubTierReward(uint256 _subTier, uint256 _subLevel, uint256 _nftId) public nonReentrant {
        require(isActive,'Not Active');

        // make sure they have unlocked this sub tier
        require(unlockedSubTiers[msg.sender][_subTier],'Sub Tier Locked');

        // see if they already claimed this sub tier
        require(claimedSubTierNfts[msg.sender][_subTier][_subLevel] <= 0, "Sub Tier already claimed");

        // make sure we have claimed the previous sub level 
        require(_subLevel == 0 || claimedSubTierNfts[msg.sender][_subTier][_subLevel-1] > 0, "Clain Previous Sub Level");
        
        // make sure the nft id is valid for that tier
        require(_isInArray(_nftId, subTiers[_subTier].nftIds[_subLevel]),"Invalid NFT" );

        require(_getSpendablePoints(msg.sender) >= subTiers[_subTier].nftCosts[_subLevel],'Not Enough Points');

        if(subTiers[_subTier].vaultPercent[_subLevel] > 0 ){
            uint256 totalVaultShares = vaultMiner.getTotalShares();
            uint256 sPer = (vaultMiner.getMyShares(msg.sender) * 10000) / totalVaultShares;
            require(sPer >= subTiers[_subTier].vaultPercent[_subLevel], 'Not Enough Shares');
        }
        
        require(subTiers[_subTier].levelLimit[_subLevel] == 0 || game.getLevel(msg.sender) >= subTiers[_subTier].levelLimit[_subLevel], 'Game level too low');

        require(subTiers[_subTier].slotsUnlocked[_subLevel] == 0 || nftStaking.getMaxSlots(msg.sender) >= subTiers[_subTier].slotsUnlocked[_subLevel], 'Unlock more NFT Slots');

        uint256 maxSupply = nft.tokenMaxSupply(_nftId);
        uint256 curSupply = nft.tokenSupply(_nftId);
        
        require(nft.balanceOf(address(this),_nftId) > 0 || (curSupply < maxSupply), 'Out of Stock');
        // burn the reward points
        _removePoints(msg.sender, subTiers[_subTier].nftCosts[_subLevel]);

        // update stats
        totalNftsClaimed = totalNftsClaimed + 1;
        subTiers[_subTier].totalClaimed = subTiers[_subTier].totalClaimed + 1;
        claimedSubTierNfts[msg.sender][_subTier][_subLevel] = _nftId;


        if(nft.balanceOf(address(this),_nftId) > 0){
            nft.safeTransferFrom(address(this), msg.sender, _nftId, 1, "0x0");
        } else {
            nft.mint(msg.sender, _nftId, 1, "0x0");
        }
        // send the NFT
        // nft.mint(_nftId, 1, "0x0");
        

        emit SubTierRewardClaimed(msg.sender, _subTier, _subLevel, _nftId, subTiers[_subTier].nftCosts[_subLevel]);
        
    }

    function getSubTierNftIds(uint256 _subTier) external view returns(uint256[][] memory) {
        return subTiers[_subTier].nftIds;
    }

    function getSubTierNftCosts(uint256 _subTier) external view returns(uint256[] memory) {
        return subTiers[_subTier].nftCosts;
    }

    function getSubTierLevelLimit(uint256 _subTier) external view returns(uint256[] memory) {
        return subTiers[_subTier].levelLimit;
    }

    function getSubTierVaultPercent(uint256 _subTier) external view returns(uint256[] memory) {
        return subTiers[_subTier].vaultPercent;
    }

    function getSubTierNftSlots(uint256 _subTier) external view returns(uint256[] memory) {
        return subTiers[_subTier].slotsUnlocked;
    }

     // return the current tier
    function getUserTier(address _user)  external view returns (uint256) {
        return userTier[_user].currentTier;
    }
/*
    function getClaimedSubTierNftIds(address _user, uint256 _subTier) external view returns(uint256[] memory){
        return unlockedSubTiers[_user][_subTier].nftIds;
    }*/

    // return the amount of points that are spendable
    function getSpendablePoints(address _user) external view returns (uint256) {
        return _getSpendablePoints(_user);
    }

    function _getSpendablePoints(address _user) internal view returns (uint256) {
        return userTier[_user].tierRewards - tiersThresh[maxTiers-1];
    }

    event TierThreshSet(uint256[] tiersThresh, uint256 maxTiers);
    function setTierThresh(uint256[] memory _tierThresh) public onlyOwner {
        tiersThresh = _tierThresh;
        maxTiers = tiersThresh.length;

        emit TierThreshSet(_tierThresh, maxTiers);
    }


    function setUserTier(address _user) internal {
        UserTier storage uTier = userTier[_user];
        uint256 length = tiersThresh.length;
        uint256 tier = 0;

        for (uint256 lvl = 0; lvl < length; ++lvl) {
            if(uTier.tierRewards >= tiersThresh[lvl] * 1 ether ){
                tier = lvl + 1;
            }
        }

        if(tier != uTier.currentTier){
            uTier.currentTier = tier;
            emit TierReached(_user, tier);
        }     
    }

    function addPoints(address _addr, uint256 _amount) public onlyAllowed {
        userTier[_addr].tierRewards = userTier[_addr].tierRewards + _amount;
        setUserTier(_addr);
        emit PointsAdded(_addr,_amount);
    }

    function removePoints(address _addr, uint256 _amount) public onlyAllowed{
        _removePoints(_addr,_amount);
    }

    function _removePoints(address _addr, uint256 _amount) private {
        // make sure this wont take them under tier 10
        uint256 newAmt = userTier[_addr].tierRewards - (_amount * 1 ether);
        require(newAmt > (tiersThresh[maxTiers-1] * 1 ether),'Must stay at tier 10');

        userTier[_addr].tierRewards = newAmt;
        setUserTier(_addr);
        emit PointsRemoved(_addr,_amount);
    }

    /**
     * @dev check if an NFT is part of a tier
     */
    function checkTierNft(uint256 _tier, uint256 _nftId) public view returns(bool){
        return _isInArray(_nftId,rewardTiers[_tier].nftIds);
    }

     /**
     * @dev check if an NFT is part of a sub-tier
     */
    function checkSubTierNft(uint256 _subTier, uint256 _subLevel, uint256 _nftId) public view returns(bool){

        return _isInArray(_nftId, subTiers[_subTier].nftIds[_subLevel]);
    }

    function bulkSetInitalPoints(
        address[] calldata _addresses, 
        uint256[] calldata _tiers,
        uint256[] calldata _points, 
        uint256[][] calldata _claims
    ) public onlyOwner {
        for (uint256 i = 0; i < _addresses.length; ++i) {
            setInitalPoints(_addresses[i], _tiers[i], _points[i], _claims[i]);
        }
    }
    /**
     * @dev since we are migrating from a different chain, it's manual. The owner can run this
     * for an account once, and only one migration is active
     */

    event InitalPointsSet(address indexed user, uint256 tier, uint256 points, uint256[] claims);
    function setInitalPoints(address _address, uint256 _tier, uint256 _points, uint256[] calldata _claims) public onlyOwner {
        require(migrationActive, 'Migration ended');
        require(!hasMigrated[_address], "Account already migrated");

        hasMigrated[_address] = true;
        userTier[_address].currentTier = _tier;
        userTier[_address].tierRewards = _points;

         for (uint256 i = 0; i < _claims.length; ++i) {
            if(_claims[i] > 0){
                claimedTiers[_address][i+1] = _claims[i];
            }
         }
         emit InitalPointsSet(_address, _tier, _points, _claims);
    }

    /** @dev set or overwrite the NFT array for a tier **/
    function setTierNfts(uint256 _tier, uint256[] memory _nftIds) public onlyOwner {
        rewardTiers[_tier].tier = _tier;
        rewardTiers[_tier].nftIds = _nftIds;
        emit SetTierNfts(msg.sender, _tier, _nftIds);
    }

    /** @dev set or overwrite the NFT array for a sub-tier **/
    function setSubTierNfts(uint256 _subTier, uint256 _subLevel, uint256[] memory _nftIds) public onlyOwner {
        subTiers[_subTier].nftIds[_subLevel] = _nftIds;
        emit SetSubTierNfts(msg.sender, _subTier, _subLevel, _nftIds);
    }
    
    function setSubTierNftsBulk(uint256 _subTier, uint256[][] memory _nftIds) public onlyOwner {       
        subTiers[_subTier].nftIds = _nftIds;

        for (uint256 i = 0; i < _nftIds.length; ++i) {
            emit SetSubTierNfts(msg.sender, _subTier, i, _nftIds[i]);
        }
    }

    event SubTierCostSet(uint256 subTier, uint256 unlockCost, uint256[] subTierNftCosts, uint256[] levelLimit, uint256[] vaultPercent, uint256[] slotsUnlocked);
    function setSubTierCosts(
        uint256 _subTier, 
        uint256 _unlockCost, 
        uint256[] memory _subTierNftCosts, 
        uint256[] memory _levelLimit, 
        uint256[] memory _vaultPercent,
        uint256[] memory _slotsUnlocked) public onlyOwner {
        subTiers[_subTier].unlockCost = _unlockCost;
        subTiers[_subTier].nftCosts = _subTierNftCosts;
        subTiers[_subTier].levelLimit = _levelLimit;
        subTiers[_subTier].vaultPercent = _vaultPercent;
        subTiers[_subTier].slotsUnlocked = _slotsUnlocked;

        emit SubTierCostSet(_subTier, _unlockCost, _subTierNftCosts, _levelLimit, _vaultPercent, _slotsUnlocked);
    }

    /**
     * @dev Update the card NFT contract address only callable by the owner
     */
    function setNftContract(ERC1155Tradable _nftAddress) public onlyOwner {
        nft = _nftAddress;
    }

    /**
     * @dev Update the card Vault contract address only callable by the owner
     */
    function setVaultMinerContract(IVaultMiner _vaultMiner) public onlyOwner {
        vaultMiner = _vaultMiner;
    }

    /**
     * @dev Update the card GameCoordinator contract address only callable by the owner
     */
    function setGameContract(IGameCoordinator _game) public onlyOwner {
        game = _game;
    }

    /**
     * @dev Update the card GameCoordinator contract address only callable by the owner
     */
    function setNftStakingContract(INftStaking _nftStaking) public onlyOwner {
        nftStaking = _nftStaking;
    }

    /**
     * @dev Global flag to enable/disable the system
     */
    event SetActive(bool isActive);
    function setActive(bool _isActive) public onlyOwner {
        isActive = _isActive;
        emit SetActive(_isActive);
    }

    function setIsAllowed(address _addr, bool _isAllowed) public onlyOwner {
        isAllowed[_addr] = _isAllowed;
    }

    /**
     * @dev since we are migrating from a different chain, it's manual.
     * when complete, end the migration forever
     */
    function endMigration() public onlyOwner {
        migrationActive = false;
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

    // @dev transfer NFTs out of the contract to be able to move into rewards on other chains or manage qty
    function transferNft(ERC1155Tradable _nftContract, uint256 _id, uint256 _amount) public onlyOwner {
      _nftContract.safeTransferFrom(address(this),address(owner()),_id, _amount, "0x00");
    }

    function onERC1155Received(address, address, uint256, uint256, bytes calldata) external pure override returns(bytes4) {
      return 0xf23a6e61;
    }


    function onERC1155BatchReceived(address, address, uint256[] calldata, uint256[] calldata, bytes calldata) external pure override returns(bytes4) {
      return 0xbc197c81;
    }

    function supportsInterface(bytes4 interfaceID) public view virtual override(IERC165) returns (bool) {
      return  interfaceID == 0x01ffc9a7 ||    // ERC-165 support (i.e. `bytes4(keccak256('supportsInterface(bytes4)'))`).
      interfaceID == 0x4e2312e0;      // ERC-1155 `ERC1155TokenReceiver` support (i.e. `bytes4(keccak256("onERC1155Received(address,address,uint256,uint256,bytes)")) ^ bytes4(keccak256("onERC1155BatchReceived(address,address,uint256[],uint256[],bytes)"))`).
  }
}
