// SPDX-License-Identifier: MIT
/// @author MrD 

pragma solidity >=0.8.11;

import "./Ownable.sol";
import "./ReentrancyGuard.sol";
import "./VRFCoordinatorV2Interface.sol";
import "./VRFConsumerBaseV2.sol";

import "./IERC20Minter.sol";

// @TODO use interfaces
import "./INftStaking.sol";
import "./INftRewards.sol";
import "./INftStore.sol";
import "./IVault.sol";
import "./IGameCoordinator.sol";
import "./IRentShares.sol";


// This is the main game contract

contract MetaBoards is Ownable, ReentrancyGuard, VRFConsumerBaseV2  {

    // Chainlink VRF
    VRFCoordinatorV2Interface COORDINATOR;
    uint64 subscriptionId;
    bytes32 internal keyHash;
    address internal vrfCoordinator;
    uint32 internal callbackGasLimit = 2500000;
    uint16 requestConfirmations = 3;
    
     // Dev address.
    address payable public feeAddress;

    // The burn address
    address public constant burnAddress = address(0xdead);   
    
    // percent of bnb to send to the vault on jackpot or rug
    uint256 public vaultPercent;

    // Game active
    bool public gameActive;

    uint256 public immutable gameId;

    // How many times a day you can reset the roll timer
    uint256 public resetTimerLimit = 5;

    // if true this board will not count for a last roll in the NFT farm
    bool public skipLastAction;

    struct Contracts {
        IERC20Minter token;
        INftStaking nftStaking;
        INftRewards nftRewards;
        // address migrator;
        IVault vault;
        address payable vaultTvl;
        IGameCoordinator gameCoordinator;
        IRentShares rentShares;
        INftStore nftStore;
    }
     struct GameSettings {
        uint256 defaultJackpot; // The amount to seed the jackpot with
        uint256 minLevel;       // Min level required to play
        uint256 maxLevel;       // Max level a player can achieve
        uint256 payDayReward;  // The amount you collect landing on go/spot 0
        uint256 chestReward; // The amount you collect landing on chest spots
        uint256 rollTimeLimit;   // time in second between rolls
        uint256 activeTimeLimit;  // time in second before a player is no longer considered active for payout
        uint256 riskMod;  // multiply all rent, rewards and taxes by this multiplier
        uint256 rollTokenBurn;  // if we should require a token burn fee to roll
        uint256 rollNativeFee;  // if we should require a bnb payment to roll
        
        uint256 levelLimit;  // what level you must be in order to claim instant rewards. Set to 0 for the first pass
        uint256 tierLimit;  // what Rewards Tier you have to be to roll Set to zero to skip the check
        uint256 minRollBalance;  // Min Token balance you must have in your wallet to roll, Set to 0 to skip this check
        bool shareRent;
//        uint256 minStakeToRoll;  // Min Cards staked to roll, Set to 0 to skip this check
    }

    struct GameStats {
        
        uint256 totalSpaces; // Total board spots
        uint256 jackpotBalance; // current jackpot balance
        uint256 totalRentPaid; // total rent ever paid
        uint256 totalRentPaidOut; // total rewards paid out
        uint256 totalPlayers; //players that rolled at least 1 time
        uint256 totalRolls; //all time total rolls
        uint256 jackpotWins; //Total times the jackpot was won
        uint256 jailCount; //Total times someone was sent to jail
        uint256 rollBurn;
        uint256 rollBnb;
    }


    //player data structure
    struct PlayerInfo {
      uint256 spotId;   // the index of the spot they are currently on.
      uint256 rentDue;      // the current rent due for this player.
      uint256 lastRoll; // the last number rolled
      uint256 lastDice1; // each dice rolled
      uint256 lastDice2;
      uint256 lastRollTime; // timestamp of the last roll
      uint256 doublesCount; // how many times in a row they rolled doubles
      bool inJail; //if this player is in jail
//      uint256 jackpotWins; //Total times the jackpot was won
//      uint256 jailCount; //Total times someone was sent to jail
      bool isRolling; //if this player is in jail

    }

    
    struct BoardInfo {
        uint256 spotType; //what type of space this is
        uint256 rent;      // the rent for this space.
        uint256 balance;  // the balance currently paid to this spot
        uint256 nftId; // Nft id's that relate to this spot
        uint256 totalPaid;  // total rent paid to this spot
        uint256 totalLanded;  // total times someone landed on this spot
        uint256 currentLanded; //how many people are currently here

        IERC20Minter partnerRewardToken;
        uint256 partnerRewardAmount;
    }

    /* 

        1 - reduce roll time
        2 - prevent you from losing a level when you get rugged
        3 - bonus  to your payday 
        4 - reduce tax and utility
        5 - reduce tax only
        6 - reduce utility only 
        7 - extra spaces
    */
    struct PowerUpInfo {
        uint256 puType; // what type of power up this is 
        uint256 puNftId; // Nft id's that relate to this power up
        uint256 puValue;  // the value that is tied to this powerup
    }

    mapping(uint256 => address) private rollQueue;
    
    GameSettings public gameSettings;
    GameStats public gameStats;
    Contracts public contracts;

    uint256 public jackpotPackId;

    uint256 public rollNowNativeFee;
    mapping(address => PlayerInfo) public playerInfo;
    mapping(uint256 => BoardInfo) public boardInfo;
    mapping(uint256 => PowerUpInfo) public powerUpInfo;
    mapping(address => uint256) private activePowerup;
    mapping(address => bool) private jackpotWhitelist;

    mapping(address => bool ) private canInteract;

    mapping(address => uint256 ) public timerResets;
    mapping(address => uint256 ) public lastReset;

    event SpotPaid(address indexed user, uint256 gameId, uint256 spotId, uint256 nftId, uint256 toRent, uint256 toBurn, uint256 toJackpot, uint256 toDev);
    event RollStarted(address indexed user, uint256 gameId, uint256 requestId, uint256 rollBurn, uint256 rollFee, uint256 timestamp);
    event RollComplete(address indexed user, uint256 gameId, uint256 roll, uint256 die1, uint256 die2, uint256 spotId, uint256 rentDue, bool isDoubles, uint256 lastRollTime);
    event LandedJackpot(address indexed user, uint256 gameId, uint256 jackpotBalance, uint256 nativeBalance, uint256 partnerRewards);
    event LandedChest(address indexed user, uint256 gameId, uint256 tokensWon, uint256 partnerRewards);
    event GotoJail(address indexed user, uint256 gameId, uint256 jackpotBalance, uint256 nativeBalance);
    event Payday(address indexed user, uint256 gameId, uint256 tokensPaid, uint256 level);
    event SuperPayday(address indexed user, uint256 gameId, uint256 tokensPaid, uint256 partnerRewards, uint256 level);
    event RentPaid(address indexed user, uint256 gameId, uint256 spotId, uint256 amount);
    event RentBurned(address indexed user, uint256 gameId, uint256 spotId, uint256 amount);
    event RentToJackpot(address indexed user, uint256 gameId, uint256 spotId, uint256 amount);
    event TimerReset(address indexed user, uint256 gameId, uint256 amount, uint256 lastRollTime);

    //-----------------------------

    constructor(
        uint256 _gameId,
        address payable _feeAddress, //dev address
        uint256[] memory _boardTypes, //an array of each board piece by type
        uint256[] memory _boardRent, //a corresponding array of each board piece by rent
        uint256[] memory _nftIds, //a corresponding array of each board piece by nftId
        address _vrfCoordinator,
        bytes32 _vrfKeyHash, 
        uint64 _subscriptionId
    ) VRFConsumerBaseV2 (
        _vrfCoordinator
    )  {

        gameId = _gameId;
        feeAddress = _feeAddress;

        //set the default board
         gameStats.totalSpaces = _boardTypes.length;
        for (uint i=0; i<gameStats.totalSpaces; i++) {
            BoardInfo storage bSpot = boardInfo[i];
            bSpot.spotType = _boardTypes[i];
            bSpot.rent = _boardRent[i];
            bSpot.nftId = _nftIds[i];
            //bSpot.balance = 0;
        }

      
        // set up chainlink
        COORDINATOR = VRFCoordinatorV2Interface(_vrfCoordinator);
        subscriptionId = _subscriptionId;
        vrfCoordinator = _vrfCoordinator;
        keyHash = _vrfKeyHash;
        
    }

    /** 
    * @notice Modifier to only allow updates by the VRFCoordinator contract
    */
    modifier onlyVRFCoordinator {
        require(msg.sender == vrfCoordinator, 'VRF Only');
        _;
    }
  

    /**
    * @dev Roll and take a players turn
    * - must not owe rent
    * - must have waited long enough between rolls
    * - sends request to chainlink VRF // noBlacklistAddress
    */
    function roll() public payable  nonReentrant returns (uint256)  {
        //roll and move
        // bool burnSuccess = false;
  
        PlayerInfo storage player = playerInfo[msg.sender];


        require(

            _canRoll(msg.sender) &&
            msg.value >= gameSettings.rollNativeFee
            , "Can't Roll");


        // check if we need to reset the roll reset
        if((lastReset[msg.sender] + 1 days) <= block.timestamp){
            timerResets[msg.sender] = 0;
        }

        // handle transfer and burns

        // if we are taking BNB transfer it to the contract
        if(gameSettings.rollNativeFee > 0){
            gameStats.rollBnb = gameStats.rollBnb + gameSettings.rollNativeFee;
        }
 
   
        // if we need to burn burn it
        if(gameSettings.rollTokenBurn > 0){
             gameStats.totalRentPaid = gameStats.totalRentPaid + gameSettings.rollTokenBurn;
             contracts.gameCoordinator.addTotalPaid(msg.sender,gameSettings.rollTokenBurn);
             gameStats.rollBurn = gameStats.rollBurn + gameSettings.rollTokenBurn;
             contracts.token.transferFrom(msg.sender, burnAddress, gameSettings.rollTokenBurn);

              // give shares
              contracts.vault.giveAdjustTokenShares(msg.sender, gameSettings.rollTokenBurn);
              // contracts.vault.giveShares(msg.sender, contracts.vault.adjustTokenShares(gameSettings.rollTokenBurn),false);
              // contracts.token.transferFrom(msg.sender, burnAddress, gameSettings.rollTokenBurn);
             // require(burnSuccess, "Burn failed");
        }

        player.isRolling = true;
  
        // PowerUpInfo storage powerUp = _getPowerUp(msg.sender);
        PowerUpInfo storage powerUp = powerUpInfo[contracts.nftStaking.getPowerUp(msg.sender)];
        // contracts.nftStaking.getPowerUp(_account)
        activePowerup[msg.sender] = powerUp.puNftId;

        //Virgin player
        if( contracts.gameCoordinator.getTotalRolls(msg.sender) < 1){
            contracts.gameCoordinator.addTotalPlayers(1);
            gameStats.totalPlayers = gameStats.totalPlayers + 1;
        }

        //inc some counters
  //      contracts.gameCoordinator.addTotalPlayers(msg.sender);

//        player.totalRolls = player.totalRolls + 1;
        gameStats.totalRolls = gameStats.totalRolls + 1;

        //check for players in jail
        if(player.inJail){
            //set them free
            player.inJail = false;
            //transport them to the jail spot 
            player.spotId = 10;
        }

        //check moon jackpot to make sure there is always something to pay out
        //this shouldn't need to happen besides the first roll
        if(gameStats.jackpotBalance <= 0){
            seedJackpot();
        }
/*
        //harvest any pending game rewards
        if(player.rewards > 0){
            _claimGameRewards();
        }
*/
        //time lock the roll
        player.lastRollTime = block.timestamp;

        // update the global last roll before we modify
        if(!skipLastAction){
            contracts.gameCoordinator.setLastRollTime(msg.sender, player.lastRollTime );
        }
        
        // check for a roll powerup
        if(powerUp.puType == 1){
            player.lastRollTime = player.lastRollTime - ((gameSettings.rollTimeLimit * powerUp.puValue)/1 ether);
        }

        // set nft staking last update
       // contracts.nftStaking.gameSetLastUpdate(msg.sender,block.timestamp);
    
        uint256 _requestId = COORDINATOR.requestRandomWords(
          keyHash,
          subscriptionId,
          requestConfirmations,
          callbackGasLimit,
          2
        );

        rollQueue[_requestId] = msg.sender;

        emit RollStarted(msg.sender, gameId, _requestId, gameSettings.rollTokenBurn, gameSettings.rollNativeFee, block.timestamp);
        return _requestId;
        

    }


     /**
     * @notice Callback function used by VRF Coordinator
     * @dev Important! Add a modifier to only allow this function to be called by the VRFCoordinator
     * @dev The VRF Coordinator will only send this function verified responses.
     * @dev The VRF Coordinator will not pass randomness that could not be verified.
     * @dev Get a number between 2 and 12, and run the roll logic
     */
      function fulfillRandomWords(
        uint256 requestId,
        uint256[] memory randomWords
      ) internal override {

        // uint256[] storage dice = new uint256[](2);
        uint256 _die1 = randomWords[0]%6 + 1;
        uint256 _die2 = randomWords[1]%6 + 1;

        address _player = rollQueue[requestId];
        // dice[0] = _die1;
        // dice[1] = _die2;
        // delete playerInfo[_player].lastDice;

        

        _doRoll(_die1,_die2,payable(_player));

      }
  /*  function fulfillRandomness(bytes32 requestId, uint256 randomness) internal override onlyVRFCoordinator {

            uint256 _roll = randomness%11 + 2;
            address _player = rollQueue[requestId];
            
            _doRoll(_roll,payable(_player));

    }
*/
    /*
    types: [
        0: 'start',
        1: 'prop',
        2: 'rr',
        3: 'util',
        4: 'chest',
        5: 'chance', 
        6: 'tax',
        7: 'jail',
        8: 'gojail',
        9: 'jackpot'
    ]
    */

    /**
     * @dev called by fulfillRandomness, process the roll and move the player
     */
    function _doRoll(uint256 _die1, uint256 _die2, address payable _player) private {
        
        bool isPropOwner =  false;
        bool doSeedJackpot = false;
        uint256 _roll = _die1 + _die2;
        bool _isDoubles = _die1 == _die2;

        uint256 payBase = (gameSettings.payDayReward * gameSettings.riskMod)/1 ether;

        
        PlayerInfo storage player = playerInfo[_player];
        uint256 playerTier = contracts.nftRewards.getUserTier(_player);
        uint256 lvl = contracts.gameCoordinator.getLevel(_player);

        PowerUpInfo storage powerUp = powerUpInfo[activePowerup[_player]];

        // check for a payday power up
        if(powerUp.puType == 3){
            payBase = (payBase * powerUp.puValue)/1 ether;
        }

        // remove the count for the current space
        if(boardInfo[player.spotId].currentLanded > 0){
            boardInfo[player.spotId].currentLanded = boardInfo[player.spotId].currentLanded - 1;
        }
        
         // check for extra spaces powerups
        if(powerUp.puType == 7){
            _roll = _roll + powerUp.puValue;
        }


        //move the player
        player.spotId = player.spotId + _roll;

        // check for a third double
        if(_isDoubles){
            player.doublesCount = player.doublesCount +1; 
            if( player.doublesCount > 2){
                // send them to the rugged space/ jail
                player.spotId = 30;
                
            }
        } else {
            player.doublesCount = 0;
        }

        //log last roll
        player.lastRoll = _roll;

        player.lastDice1 = _die1;
        player.lastDice2 = _die2;

        if(!skipLastAction){
            // harvest the NFT farms
            contracts.nftStaking.gameHarvest(_player);
        }

        //check if we passed go
        if(player.spotId >= gameStats.totalSpaces){

          

          if(lvl < gameSettings.maxLevel){
            lvl = lvl + 1;
            contracts.gameCoordinator.setLevel(_player,lvl);
          }

          player.spotId = player.spotId - gameStats.totalSpaces;
          
          //don't pay them twice
          if(player.spotId != 0){
            //multiply by the level or the max level for this board
            uint256 lBase = payBase * lvl;

            if(lvl > gameSettings.maxLevel){
                lBase = payBase * gameSettings.maxLevel;
            }
            gameStats.totalRentPaidOut = gameStats.totalRentPaidOut + lBase;
            // player.rewards = player.rewards + lBase;
            contracts.rentShares.addPendingRewards(_player, lBase);
            contracts.token.mint(address(contracts.rentShares), lBase);
            emit Payday(_player, gameId, lBase, lvl);
          }
        }

        BoardInfo storage bSpot = boardInfo[player.spotId];

        //some stats
        bSpot.totalLanded = bSpot.totalLanded + 1;
        bSpot.currentLanded = bSpot.currentLanded + 1;

        //set the rent
        uint256 rent = (bSpot.rent * gameSettings.riskMod)/1 ether;
        
        //check the spot type
        if(bSpot.spotType == 0){
            //landed on go mint 4x the pay day x the level up to the max level for this board
            uint256 lBase = payBase * 4 * lvl;

            if(lvl > gameSettings.maxLevel){
                lBase = payBase * 4 * gameSettings.maxLevel;
            }

            gameStats.totalRentPaidOut =  gameStats.totalRentPaidOut + lBase;
            // player.rewards = player.rewards + lBase;
            contracts.rentShares.addPendingRewards(_player, lBase);
            contracts.token.mint(address(contracts.rentShares), lBase);

            // see if we have partner rewards
            if(bSpot.partnerRewardToken != IERC20Minter(address(0x0)) && bSpot.partnerRewardAmount != 0){
                // make sure we still have a balance
                if(bSpot.partnerRewardToken.balanceOf(address(this)) > 0){
                    // send the partner rewards
                    safePartnerTransfer(bSpot.partnerRewardToken, _player, bSpot.partnerRewardAmount);
                }
            }

           emit SuperPayday(_player, gameId, lBase, bSpot.partnerRewardAmount, lvl);
        }

        if(bSpot.spotType == 1 || bSpot.spotType == 2){
            //property and rocket
            //don't pay rent for our own property
            isPropOwner = _isStaked(_player, player.spotId);
            if(isPropOwner){
                rent = 0;
            }
        }


        if(bSpot.spotType == 3){
            /*
            @dev Utility
            rent is base rent X the roll so we can have varying util rents
            ie: 
            - first util spot rent is 4 so (4x the roll)
            - second util spot rent is 8 so (8x the roll)
            */
            if(lvl < gameSettings.levelLimit || playerTier < gameSettings.tierLimit){
                rent = 0;
            } else {
                rent = rent * _roll;
                // check for utility power up
                if(powerUp.puType == 4 || powerUp.puType == 6){
                    rent = (rent * powerUp.puValue)/1 ether;
                }
            }
        }

        // @dev make sure they players level is at the proper level to earn instant rewards
        if(bSpot.spotType == 4 && lvl >= gameSettings.levelLimit && playerTier >= gameSettings.tierLimit){
            //community chest
            uint256 modChestReward = (gameSettings.chestReward * gameSettings.riskMod)/1 ether;

            gameStats.totalRentPaidOut =  gameStats.totalRentPaidOut + modChestReward;
            // player.rewards = player.rewards + modChestReward;
            contracts.rentShares.addPendingRewards(_player, modChestReward);
            contracts.token.mint(address(contracts.rentShares), modChestReward);

            // see if we have partner rewards
            if(bSpot.partnerRewardToken != IERC20Minter(address(0x0)) && bSpot.partnerRewardAmount != 0){
                // make sure we still have a balance
                if(bSpot.partnerRewardToken.balanceOf(address(this)) > 0){
                    // send the partner rewards
                    safePartnerTransfer(bSpot.partnerRewardToken, _player, bSpot.partnerRewardAmount);
                }
            }

           emit LandedChest(_player, gameId, modChestReward, bSpot.partnerRewardAmount);
            
        }

        if(bSpot.spotType == 5 || (_isDoubles && player.doublesCount < 3)){
            //roll again
            //get a free roll, set the timestamp back 
            player.lastRollTime = block.timestamp - gameSettings.rollTimeLimit;
        }

        if(bSpot.spotType == 6){
            if(lvl < gameSettings.levelLimit || playerTier < gameSettings.tierLimit){
                // since we don't give rewards we shouldn't charge tax
                rent = 0;
            } else {
                // check for a tax power up
                if(powerUp.puType == 4 || powerUp.puType == 5){
                    rent = (rent * powerUp.puValue)/1 ether;
                }
            }
        }

        if(bSpot.spotType == 8){
            //go to jail
            bool validRug;
            // see if we have a level shield powerup
            if(powerUp.puType != 2){
                //take away a level
                if(lvl > 0){                
                    lvl = lvl - 1;
                    contracts.gameCoordinator.setLevel(_player,lvl);
                    validRug = true;
                }
            }
            //flag player in jail
            player.inJail = true;
//            player.jailCount = player.jailCount + 1;
            gameStats.jailCount = gameStats.jailCount + 1;

            //Clear the jackpot
            uint256 _pbal = gameStats.jackpotBalance;
            gameStats.jackpotBalance = 0;

            //lock them for 3 rolls time
            player.lastRollTime = block.timestamp + (gameSettings.rollTimeLimit * 2);

            // reset the doubles count
            player.doublesCount = 0;
            // check for a roll powerup
            if(powerUp.puType == 1){
                player.lastRollTime = player.lastRollTime - ((gameSettings.rollTimeLimit * 3 * powerUp.puValue)/1 ether);
            }

            emit GotoJail(_player, gameId, _pbal, address(this).balance);

           /*  )
              ) \  
             / ) (  
             \(_)/ */
            //Burn the jackpot!!! 
            safeTokenTransfer(address(burnAddress), _pbal);

            // transfer BNB to the dev wallet
            if(validRug && address(this).balance > 0){
               
                // send 20% to the vault
                uint256 cBal = address(this).balance;
                uint256 toVault = (cBal * vaultPercent)/100;

                bool sent;
                (sent, ) = payable(address(contracts.vaultTvl)).call{value: toVault}("");
                require(sent, "Failed to send");

                 // the rest to the dev
                (sent, ) = payable(address(feeAddress)).call{value: cBal - toVault}("");
                require(sent, "Failed to send");
               
                // feeAddress.transfer(cBal - toVault);
            }

            //re-seed the jackpot
            doSeedJackpot = true;

        }

        // @dev make sure they players level is at the proper level to earn instant rewards
        if(bSpot.spotType == 9 && lvl >= gameSettings.levelLimit && playerTier >= gameSettings.tierLimit){
            //Moon Jackpot
            //WINNER WINNER CHICKEN DINNER!!!
            if(gameStats.jackpotBalance > 0){
                //send the winner the prize
                uint256 _pbal = gameStats.jackpotBalance;
                
                gameStats.jackpotBalance = 0;


                if(!jackpotWhitelist[_player]){
                    // whitelist this jackpot pack
                    if(jackpotPackId > 0){
                        jackpotWhitelist[_player] = true;
                        contracts.nftStore.addPackWhitelist(jackpotPackId,_player);
                    }
                }

                emit LandedJackpot(_player, gameId, _pbal, address(this).balance, bSpot.partnerRewardAmount);
                // transfer BNB to the winner
                if(address(this).balance > 0){
                    // send 20% to the vault
                    uint256 toVault = (address(this).balance * vaultPercent)/100;
                    uint256 toWinner = address(this).balance - toVault;

                    bool sent;
                    (sent, ) = payable(address(contracts.vaultTvl)).call{value: toVault}("");
                    require(sent, "Failed to send");

                    // the rest to the winner
                    (sent, ) = payable(address(_player)).call{value: toWinner}("");
                    require(sent, "Failed to send");
                   // _player.transfer(toWinner);

                }

                // player.rewards = player.rewards + _pbal;
                // transfer to the rent share contract
                contracts.rentShares.addPendingRewards(_player, _pbal);
                safeTokenTransfer(address(contracts.rentShares), _pbal);

                // see if we have partner rewards
                if(bSpot.partnerRewardToken != IERC20Minter(address(0x0)) && bSpot.partnerRewardAmount != 0){
                    // make sure we still have a balance
                    if(bSpot.partnerRewardToken.balanceOf(address(this)) > 0){
                        // send the partner rewards
                        safePartnerTransfer(bSpot.partnerRewardToken, _player, bSpot.partnerRewardAmount);
                    }
                }

                

                gameStats.jackpotWins = gameStats.jackpotWins + 1;
                gameStats.totalRentPaidOut =  gameStats.totalRentPaidOut + _pbal;
                //reset the jackpot balance
                doSeedJackpot = true;
            }
        }


        if(doSeedJackpot){
            seedJackpot();
        }

        player.isRolling = false;
        player.rentDue = rent;

         emit RollComplete(_player, gameId, _roll, player.lastDice1, player.lastDice2, player.spotId, rent, _isDoubles, player.lastRollTime);
    }


     //-----------------------------

     /**
      * @dev Set all the base game settings in one function to reduce code
      */
    event GameSettingsSet(
        uint256 gameId,
        uint256 riskMod, 
        uint256 minLevel, 
        uint256 maxLevel, 
        uint256 defaultJackpot, 
        uint256 payDayReward, 
        uint256 chestReward, 
        uint256 rollTimeLimit, 
        uint256 activeTimeLimit, 
        bool shareRent, 
        uint256 vaultPercent, 
        uint256 resetTimerLimit
    );  

    function setGameSettings( 
        
        uint256 _riskMod,
        uint256 _minLevel, // min level to play
        uint256 _maxLevel, //the level cap for players
        uint256 _defaultJackpot, //the value of a fresh jackpot
        uint256 _payDayReward, //the value of landing on go, (payDayReward/10) for passing it
        uint256 _chestReward, //value to mint on a chest spot
        uint256 _rollTimeLimit, //seconds between rolls
        uint256 _activeTimeLimit, //seconds since last roll before a player is ineligible for payouts
        bool _shareRent, // if we are sending rent to players or burning it
        uint256 _vaultPercent,
        uint256 _resetTimerLimit,
        bool _skipLastAction
    ) public onlyOwner {
        
        gameSettings.riskMod = _riskMod;
        gameSettings.minLevel = _minLevel;
        gameSettings.maxLevel = _maxLevel;
        gameSettings.defaultJackpot = _defaultJackpot;
        gameSettings.payDayReward = _payDayReward;
        gameSettings.chestReward = _chestReward;
        gameSettings.rollTimeLimit = _rollTimeLimit;
        gameSettings.activeTimeLimit = _activeTimeLimit;
        gameSettings.shareRent = _shareRent;
        vaultPercent = _vaultPercent;
        resetTimerLimit = _resetTimerLimit;
        skipLastAction = _skipLastAction;

        emit GameSettingsSet(
            gameId,
            _riskMod,
            _minLevel,
            _maxLevel,
            _defaultJackpot,
            _payDayReward,
            _chestReward,
            _rollTimeLimit,
            _activeTimeLimit,
            _shareRent,
            _vaultPercent,
            _resetTimerLimit
        ); 
    }

    /**
      * @dev Set roll limits in one funtion to reduce code
      */
     event RollSettingsSet(
        uint256 gameId, 
        uint256 rollTokenBurn, 
        uint256 rollNativeFee, 
        uint256 levelLimit, 
        uint256 tierLimit, 
        uint256 minRollBalance, 
        uint256 rollNowNativeFee
    );

    function setRollSettings( 
        uint256 _rollTokenBurn, // amount of tokens to burn on every roll
        uint256 _rollNativeFee, // amount of bnb to charge for every roll
        uint256 _levelLimit, // min in game level to get rewards or pay rent
        uint256 _tierLimit, // min LP tier to get rewards or pay rent
        uint256 _minRollBalance, // amount of Tokens you must have in your wallet to roll
        uint256 _rollNowNativeFee

//        uint256 _minStakeToRoll // min amount of cards staked to be able to roll
    ) public onlyOwner {
        gameSettings.rollTokenBurn = _rollTokenBurn;
        gameSettings.rollNativeFee = _rollNativeFee;
        gameSettings.levelLimit = _levelLimit;
        gameSettings.tierLimit = _tierLimit;
        gameSettings.minRollBalance = _minRollBalance;
        rollNowNativeFee = _rollNowNativeFee;
//        gameSettings.minStakeToRoll = _minStakeToRoll;

        emit RollSettingsSet(
            gameId,
            _rollTokenBurn,
            _rollNativeFee,
            _levelLimit,
            _tierLimit,
            _minRollBalance,
            _rollNowNativeFee
        );
    }
    
    
    /**
    * @dev See if a player has a valid card staked and has recently rolled
    */
    function _isStaked(address _account, uint256 _spotId) private view returns(bool){

        if(boardInfo[_spotId].nftId == 0){
            return false;
        }

        // instead of getting all the staked cards, see if they have rent shares for this NFT
        if(contracts.rentShares.getRentShares(_account, boardInfo[_spotId].nftId) > 0){
            return true;
        }

        return false;

    }

    /**
    * @dev Assign or update a specific NftId as a power up
    */

    event PowerUpAdded(uint256 gameId, uint256 nftId, uint256 puType, uint256 puValue);
    function setPowerUp(uint256 _puNftId, uint256 _puType, uint256 _puValue) public onlyOwner {
        powerUpInfo[_puNftId].puNftId = _puNftId;
        powerUpInfo[_puNftId].puType = _puType;
        powerUpInfo[_puNftId].puValue = _puValue;
        emit PowerUpAdded(gameId, _puNftId, _puType, _puValue);
    }


    /**
    * @dev Handle paying a players rent/tax 
    */
    
    function payRent() public nonReentrant {

            
        bool transferSuccess = false;
         // BoardInfo storage bSpot = boardInfo[_spotId];
        PlayerInfo storage player = playerInfo[msg.sender];

        uint256 _rentDue = player.rentDue;
        uint256 tokenBal = contracts.token.balanceOf(msg.sender);

        require(gameActive && _rentDue > 0 && tokenBal >= _rentDue, "Can't pay");

         //if we don't have full rent take what we can get
        if(tokenBal < _rentDue){
            _rentDue = tokenBal;
        }

        //pay the rent internally 
        player.rentDue = player.rentDue - _rentDue;
        transferSuccess = contracts.token.transferFrom(address(msg.sender),address(this),_rentDue);
        require(transferSuccess, "transfer failed");

        if(boardInfo[player.spotId].spotType == 3){
            //utils are community add to the moon jackpot
            gameStats.jackpotBalance = gameStats.jackpotBalance + _rentDue;
            emit RentToJackpot(msg.sender, gameId, player.spotId, _rentDue);
        } else if(boardInfo[player.spotId].spotType == 6){

           /*  )
              ) \  
             / ) (  
             \(_)/ */
            //Burn all taxes 
            safeTokenTransfer(address(burnAddress), _rentDue);
            emit RentBurned(msg.sender, gameId, player.spotId, _rentDue);
        } else {
            //pay the spot and run payouts for all the stakers
            boardInfo[player.spotId].balance = boardInfo[player.spotId].balance + _rentDue;
            _payOutSpot(player.spotId);
            
        }

        //keep track of the total paid stats
        gameStats.totalRentPaid = gameStats.totalRentPaid + _rentDue;
        contracts.gameCoordinator.addTotalPaid(msg.sender, _rentDue);
//        player.totalRentPaid = player.totalRentPaid + _rentDue;
        boardInfo[player.spotId].totalPaid = boardInfo[player.spotId].totalPaid + _rentDue;

        emit RentPaid(msg.sender, gameId, player.spotId, _rentDue);
    }

    
    function resetTimer() public payable nonReentrant {
        uint256 timerEnd = playerInfo[msg.sender].lastRollTime + gameSettings.rollTimeLimit;
        require(gameActive,'Game Not Active');
        require(block.timestamp < timerEnd,'Timer Expired');
        require(msg.value >= rollNowNativeFee,'Low Balance');
        require(timerResets[msg.sender] < resetTimerLimit, "Too many resets");


        gameStats.rollBnb = gameStats.rollBnb + rollNowNativeFee;
        playerInfo[msg.sender].lastRollTime = block.timestamp - gameSettings.rollTimeLimit;

        lastReset[msg.sender] = block.timestamp;
        timerResets[msg.sender] = timerResets[msg.sender] + 1;
        emit TimerReset(msg.sender, gameId,msg.value,playerInfo[msg.sender].lastRollTime);

    }

    /**
     * @dev allowed external contracts can reset the players roll timer
     * for 3rd party hooks into other p2e contracts
     * */
    function contractResetTimer(address _player) public {
        require(canInteract[msg.sender],'nope');
        require(gameActive,'Game Not Active');

        uint256 timerEnd = playerInfo[_player].lastRollTime + gameSettings.rollTimeLimit;
        
        if(block.timestamp < timerEnd){
            playerInfo[msg.sender].lastRollTime = block.timestamp - gameSettings.rollTimeLimit;
        }

        emit TimerReset(_player, gameId,0,block.timestamp);

    }

    /**
     * @dev Pays out all the stakers of this spot and resets its balance.
     *
     * // Emits a {SpotPaid} 
     *
     * Payouts are distributed like so:
     * 10% - burned forever
     * 10% - sent to the jackpot
     * 5% - sent to dev address
     * 75% - split evenly between all stakers (active or not)
     * - To be eligible to receive the payout the player must have the card staked and rolled in the last day
     * - Any staked share that is not eligible will be burned
     * 
     *
     * Requirements
     *
     * - `_spotId` cannot be the zero address.
     * - `account` must have at least `amount` tokens.
    */
    function _payOutSpot(uint256 _spotId) internal {
    //get all the addresses that have this card staked
    //total up the stakers
        require(_spotId + 1 <= gameStats.totalSpaces && boardInfo[_spotId].balance > 0, "Invalid");

        uint256 totalToDistribute = boardInfo[_spotId].balance;

        //10% to burn
        uint256 toBurn = (totalToDistribute * 10)/100;

        //10% to jackpot
        uint256 toJackpot = (totalToDistribute * 10)/100;

        //5% to dev
        uint256 toDev = (totalToDistribute * 5)/100;

        //clear the spot balance
        boardInfo[_spotId].balance = 0;
        uint256 toSend = 0;
        if(gameSettings.shareRent){
            toSend = totalToDistribute - toBurn - toJackpot - toDev;
            if(contracts.rentShares.totalRentSharePoints(boardInfo[_spotId].nftId) > 0){
                contracts.rentShares.collectRent(boardInfo[_spotId].nftId,toSend);
            } else {
                toBurn = toBurn + toSend;
            }

        } else {
            // no distribution burn a lot more!
            
            //20% to jackpot
            toJackpot = (totalToDistribute * 20)/100;

            //5% to dev
            toDev = (totalToDistribute * 5)/100;

            //75% to burn
            toBurn = totalToDistribute - toJackpot - toDev;
        }


        gameStats.jackpotBalance = gameStats.jackpotBalance + toJackpot;
       /*  )
          ) \  
         / ) (  
         \(_)/ */
        //burn it!
        safeTokenTransfer(address(burnAddress), toBurn);
        safeTokenTransfer(feeAddress,toDev);

        //emit SpotPaid(_spotId, origBal, share, totalToDistribute, toJackpot, toBurn, toDev, stakers);
        
        emit SpotPaid(msg.sender, gameId, _spotId, boardInfo[_spotId].nftId,toSend,toBurn,toJackpot,toDev );
    }
     
    /**
    * @dev reset the jackpot
    */
    event JackpotReset(uint256 gameId, uint256 amount);
    function seedJackpot() internal {
         //seed the jackpot
        gameStats.jackpotBalance = (gameSettings.defaultJackpot * gameSettings.riskMod)/1 ether;
        contracts.token.mint(address(this), gameStats.jackpotBalance);
        emit JackpotReset(gameId, gameStats.jackpotBalance);
    }

    /**
    * @dev Add to the jackpot used for promos or for any generous soul to give back
    */
    event JackpotAdd(address indexed user, uint256 gameId, uint256 amount);
    function addJackpot(uint256 _amount) public nonReentrant {
             // manually add to the jackpot 
            require(_amount > 0 && contracts.token.balanceOf(msg.sender) >= _amount, "Nothing to add");


            gameStats.jackpotBalance = gameStats.jackpotBalance + _amount;

            // transferSuccess = contracts.token.transferFrom(address(msg.sender),address(this),_amount);
            contracts.token.transferFrom(address(msg.sender),address(this),_amount);
            emit JackpotAdd(msg.sender, gameId, _amount);

    }

    /**
    * @dev Update the details on a space
    */
    event SpotUpdated(uint256 gameId, uint256 spotId, uint256 spotType, uint256 rent, uint256 nftId, address partnerRewardToken, uint256 partnerRewardAmount);
    function updateSpot(
        uint256 _spotId,  
        uint256 _spotType, 
        uint256 _rent,
        uint256 _nftId,
        IERC20Minter _partnerRewardToken,
        uint256 _partnerRewardAmount) public onlyOwner {

            boardInfo[_spotId].spotType = _spotType;
            boardInfo[_spotId].rent = _rent;
            boardInfo[_spotId].nftId = _nftId;
            boardInfo[_spotId].partnerRewardToken = _partnerRewardToken;
            boardInfo[_spotId].partnerRewardAmount = _partnerRewardAmount;
            emit SpotUpdated(gameId, _spotId, _spotType, _rent, _nftId, address(_partnerRewardToken),  _partnerRewardAmount);
    }

    function canRoll(address _account) external view returns(bool){

        return _canRoll(_account);
    }

    function _canRoll(address _account) private view returns(bool) {
        uint256 tokenBal = contracts.token.balanceOf(_account);

        if(
            !gameActive || 
            contracts.gameCoordinator.getLevel(_account) < gameSettings.minLevel ||
            playerInfo[_account].isRolling || 
            playerInfo[_account].rentDue > 0 || 
            block.timestamp < playerInfo[_account].lastRollTime + gameSettings.rollTimeLimit ||
            tokenBal < gameSettings.rollTokenBurn  ||
            tokenBal < gameSettings.minRollBalance
        ){
            return false;
        }
        return true;
    }

    function playerActive(address _account) external view returns(bool){
        return _playerActive(_account);
    }

    function _playerActive(address _account) internal view returns(bool){
        if(block.timestamp <= playerInfo[_account].lastRollTime + gameSettings.activeTimeLimit){
            return true;
        }
        return false;
    }


    // Safe token transfer function, just in case if rounding error causes pool to not have enough Tokens.
    function safeTokenTransfer(address _to, uint256 _amount) internal {
        uint256 tokenBal = contracts.token.balanceOf(address(this));
        bool transferSuccess = false;
        if (_amount > tokenBal) {
            transferSuccess = contracts.token.transfer(_to, tokenBal);
        } else {
            transferSuccess = contracts.token.transfer(_to, _amount);
        }
        require(transferSuccess, "transfer failed");
    }

    function safePartnerTransfer(IERC20Minter _partnerRewardToken, address _to, uint256 _amount) internal {
        uint256 tokenBal = _partnerRewardToken.balanceOf(address(this));
        bool transferSuccess = false;
        if (_amount > tokenBal) {
            transferSuccess = _partnerRewardToken.transfer(_to, tokenBal);
        } else {
            transferSuccess = _partnerRewardToken.transfer(_to, _amount);
        }
        require(transferSuccess, "transfer failed");
    }

    /**
     * @dev if a VRF return fails for any reason this lets us reset the isRolling flag and save the account
     */
    function resetIsRolling(address _player) public onlyOwner {
        playerInfo[_player].isRolling = false;        
    }
/*
    function endMigration() public onlyOwner{
        migrationActive = false;
    }

    function updatePlayer (
        address _address, 
        uint256 _spotId, 
        uint256 _rentDue, 
        uint256 _lastRoll,
        uint256 _lastRollTime,
        bool _inJail
        ) public {
        
        require(migrationActive && !hasMigrated[_address] && msg.sender == contracts.migrator, "already migrated");

        hasMigrated[_address] = true;
        playerInfo[_address].spotId = _spotId;
        playerInfo[_address].rentDue = _rentDue;
        playerInfo[_address].lastRoll = _lastRoll;
        playerInfo[_address].lastRollTime = _lastRollTime;
        playerInfo[_address].inJail = _inJail;

    }
*/
    event JackpotPackSet(uint256 gameId, uint256 packId);
    function setJackpotPack(uint256 _jackpotPackId) public onlyOwner { // which jackpot WL pack is tied to this game
        jackpotPackId = _jackpotPackId;
        emit JackpotPackSet(gameId, _jackpotPackId);
    }
    /**
    * @dev Set the game active 
    */

    event GameSetActive(uint256 gameId, bool isActive);
    function setGameActive(bool _isActive) public onlyOwner {
        gameActive = _isActive;
        emit GameSetActive(gameId, _isActive);
    }

    function setCanInteract(address _addr, bool _canInteract) public onlyOwner {
        canInteract[_addr] = _canInteract;
    }

    // Update dev address by the previous dev.
    function dev(address payable _feeAddress) public onlyOwner{
        feeAddress = _feeAddress;
    }


    function setContracts(
        IERC20Minter _token, 
        INftStaking _nftStakingAddress,
        INftRewards _nftRewards, 
        // address _migrator, 
        IVault _vault, 
        address payable _vaultTvl,
        IGameCoordinator _gameCoordinator, 
        IRentShares _rentSharesAddress,
        INftStore _nftStoreAddress) public onlyOwner{
        contracts.token = _token;
        contracts.nftStaking = _nftStakingAddress;
        contracts.nftRewards = _nftRewards;
        // contracts.migrator = _migrator;
        contracts.vault = _vault;
        contracts.vaultTvl = _vaultTvl;
        contracts.gameCoordinator = _gameCoordinator;
        contracts.rentShares = _rentSharesAddress;
        contracts.nftStore = _nftStoreAddress;

        contracts.token.approve(address(_rentSharesAddress), type(uint256).max);

    }

    function setLinkGas(uint32 _callbackGasLimit) public onlyOwner {
      callbackGasLimit = _callbackGasLimit;
    }

    /**
     * @dev If we need to migrate contracts we need a way to get the BNB out of it
     */ 
    function withdrawNative() public onlyOwner{
        (bool sent, ) = payable(address(feeAddress)).call{value: address(this).balance}("");
        require(sent, "Failed to send");
        // feeAddress.transfer(address(this).balance);
    }


    function withdrawPartnerToken(IERC20Minter _partnerRewardToken) public onlyOwner {
        safePartnerTransfer(_partnerRewardToken, address(owner()), _partnerRewardToken.balanceOf(address(this)));
    }

    /**
     * @dev Accept native tokens 
     */ 
    fallback() external  payable { }
    receive() external payable { }

}
