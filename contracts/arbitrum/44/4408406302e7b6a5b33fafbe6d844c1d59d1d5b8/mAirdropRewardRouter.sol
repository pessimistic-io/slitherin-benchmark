/*                               %@@@@@@@@@@@@@@@@@(                              
                        ,@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@                        
                    /@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@.                   
                 &@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@(                
              ,@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@              
            *@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@            
           @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@          
         &@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@*        
        @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@&       
       @@@@@@@@@@@@@   #@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@   &@@@@@@@@@@@      
      &@@@@@@@@@@@    @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@.   @@@@@@@@@@,     
      @@@@@@@@@@&   .@@@@@@@@@@@@@@@@@&@@@@@@@@@&&@@@@@@@@@@@#   /@@@@@@@@@     
     &@@@@@@@@@@    @@@@@&                 %          @@@@@@@@,   #@@@@@@@@,    
     @@@@@@@@@@    @@@@@@@@%       &&        *@,       @@@@@@@@    @@@@@@@@%    
     @@@@@@@@@@    @@@@@@@@%      @@@@      /@@@.      @@@@@@@@    @@@@@@@@&    
     @@@@@@@@@@    &@@@@@@@%      @@@@      /@@@.      @@@@@@@@    @@@@@@@@/    
     .@@@@@@@@@@    @@@@@@@%      @@@@      /@@@.      @@@@@@@    &@@@@@@@@     
      @@@@@@@@@@@    @@@@&         @@        .@          @@@@.   @@@@@@@@@&     
       @@@@@@@@@@@.   @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@    @@@@@@@@@@      
        @@@@@@@@@@@@.  @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@   @@@@@@@@@@@       
         @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@        
          @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@#         
            @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@           
              @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@             
                &@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@/               
                   &@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@(                  
                       @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@#                      
                            /@@@@@@@@@@@@@@@@@@@@@@@*  */
// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "./Ownable.sol";
import "./ReentrancyGuard.sol";
import "./SafeMath.sol";
import "./SafeERC20.sol";


/*
Recoge los airdrop de las diferentes wallets
Destina una cantidad para cada wallet de usuario
*/
contract mAirdropRewardRouter is Ownable, ReentrancyGuard{

    //Libraries
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    //Structures
    struct Airdrop{
        IERC20 token;
        uint256 date;
        uint256 expirationDate;
        uint256 totalAmount;
        uint256 availableAmount;
        uint256 totalShares;
        uint256 totalBonusShares;
        uint256 bonusBasisPoints;
    }
    struct AirdropShare{
        uint256 shares;
        uint256 bonusShares;
    }
    struct BulkShareUser{
        address user;
        uint256 shares;
        uint256 bonusShares;
    }
    struct AirdropReward{
        uint256 airdropId;
        uint256 normalAmount;
        uint256 bonusAmount;
    }


    //Attributes
    uint256 public maxTimeForHarvest;

    //Data
    Airdrop[] public airdrops;
    uint256 numAirdrops;
    mapping(uint256 => mapping(address => AirdropShare)) public airdropUserShares;
    

    //Events
    event Deposited(IERC20 token, uint256 amount);
    event AirdropSharesSet(uint256 airdropId, address user, uint256 shares, uint256 bonusShares);
    event Harvest(uint256 airdropId, address user, uint256 amount);
    event HarvestExpired(uint256 airdropId, address user, uint256 amount);



    //Setters
    function setMaxTimeForHarvest(uint256 time) external onlyOwner{
        maxTimeForHarvest = time;
    }


    //Read methods
    function userAirdropRewards(uint256 airdropId) external view returns(uint256 normalRewards, uint256 bonusRewards){
        (normalRewards, bonusRewards) = _userAirdropRewards(airdropId, msg.sender);
    }

    function userAllAirdropRewards() external view returns(AirdropReward[] memory rewards){
        rewards = new AirdropReward[](airdrops.length);
        for(uint256 i = 0; i < airdrops.length; i++){
            (uint256 normalRewards, uint256 bonusRewards) = _userAirdropRewards(i, msg.sender);
            rewards[i] = AirdropReward({airdropId: i, normalAmount: normalRewards, bonusAmount: bonusRewards});
        }
    }


    //Write Methods
    function depositAirdrop(IERC20 tokenIn, uint256 bonusBP, address[] calldata wallets) external onlyOwner returns(uint256){
        require(bonusBP < 10000, "mAirdropRewardRouter.depositAirdrop: invalid bonus basis points");
        uint256 totalAmount;
        for(uint256 i = 0; i < wallets.length; i++){
            uint256 amount = tokenIn.balanceOf(wallets[i]);
            if(amount > 0){
                tokenIn.safeTransferFrom(wallets[i], address(this), amount);
                totalAmount += amount;
            }
        }

        require(totalAmount > 0, "mAirdropRewardRouter.depositAirdrop: 0 amount in wallets");

        airdrops.push(Airdrop({token: tokenIn, date: block.timestamp, expirationDate: block.timestamp + maxTimeForHarvest, totalAmount: totalAmount, availableAmount: totalAmount, totalShares: 0, totalBonusShares: 0, bonusBasisPoints: bonusBP}));
        numAirdrops += 1;
        emit Deposited(tokenIn, totalAmount);

        return airdrops.length - 1;
    }

    function setUserAirdropShares(uint256 airdropId, address user, uint256 shares, uint256 bonusShares) external onlyOwner{
        _setUserAirdropShares(airdropId, user, shares, bonusShares);
    }

    function bulkSetUserAirdropShares(uint256 airdropId, BulkShareUser[] calldata userShares) external onlyOwner{
        for(uint256 i = 0; i < userShares.length; i++){
            _setUserAirdropShares(airdropId, userShares[i].user, userShares[i].shares, userShares[i].bonusShares);
        }
    }

    function harvest(uint256 airdropId) public returns(uint256 amount){
        (uint256 normalRewards, uint256 bonusRewards) = _userAirdropRewards(airdropId, msg.sender);
        amount = normalRewards + bonusRewards;

        if(amount > 0){
            amount = _withdrawAmount(airdropId, amount);
            airdropUserShares[airdropId][msg.sender].shares = 0;
            airdropUserShares[airdropId][msg.sender].bonusShares = 0;
            emit Harvest(airdropId, msg.sender, amount);
        }
    }

    function harvestAll() external{
        for(uint256 i = 0; i < airdrops.length; i++){
            harvest(i);
        }
    }

    function harvestExpired(uint256 airdropId) external onlyOwner returns(uint256 amount){
        require(airdrops[airdropId].availableAmount > 0, "mAirdropRewardRouter: No available amount");
        require(airdrops[airdropId].expirationDate < block.timestamp, "mAirdropRewardRouter: Not expired yet");

        amount = _withdrawAmount(airdropId, airdrops[airdropId].availableAmount);

        emit HarvestExpired(airdropId, msg.sender, amount);
    }


    //Internal methods
    function _setUserAirdropShares(uint256 airdropId, address user, uint256 shares, uint256 bonusShares) internal{
        AirdropShare memory currentShare = airdropUserShares[airdropId][user];

        //Normal shares
        airdrops[airdropId].totalShares = airdrops[airdropId].totalShares.add(shares).sub(currentShare.shares);
        airdropUserShares[airdropId][user].shares = shares;

        //Bonus shares
        airdrops[airdropId].totalBonusShares = airdrops[airdropId].totalBonusShares.add(bonusShares).sub(currentShare.bonusShares);
        airdropUserShares[airdropId][user].bonusShares = bonusShares;

        emit AirdropSharesSet(airdropId, user, shares, bonusShares);
    }

    function _withdrawAmount(uint256 airdropId, uint256 amount) internal returns(uint256 amountWithdrawn){
        amountWithdrawn = amount;

        //Round issues
        if(amountWithdrawn > airdrops[airdropId].token.balanceOf(address(this))){
            amountWithdrawn = airdrops[airdropId].token.balanceOf(address(this));
        }

        airdrops[airdropId].token.safeTransfer(msg.sender, amountWithdrawn);
        airdrops[airdropId].availableAmount -= amountWithdrawn;
    }

    function _userAirdropRewards(uint256 airdropId, address user) internal view returns(uint256 normalRewards, uint256 bonusRewards){
        normalRewards = airdrops[airdropId].totalAmount
                                .mul(10000 - airdrops[airdropId].bonusBasisPoints)
                                .mul(airdropUserShares[airdropId][user].shares)
                                .div(airdrops[airdropId].totalShares)
                                .div(10000);

        bonusRewards = airdrops[airdropId].totalAmount
                                .mul(airdrops[airdropId].bonusBasisPoints)
                                .mul(airdropUserShares[airdropId][user].bonusShares)
                                .div(airdrops[airdropId].totalBonusShares)
                                .div(10000);
    }
    
}
