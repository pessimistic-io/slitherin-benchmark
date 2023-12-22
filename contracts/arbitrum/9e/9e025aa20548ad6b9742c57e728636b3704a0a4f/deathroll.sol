                                                
//                   #%%%%%%*                       
//                     %%%%%%%%%%%%%%%              
//                      %%%%%%%%%%%%%%%             
//        #%              %%%%%%%%%%%%%%            
//          %%%%%%%%%%,    %%%%%%%%%%%%%%,          
//           .%%%%%%%%%%%%%%%%%%%%%%%%%%%%%         
//             %%%%%%%%%%%%%%%%%%%%%%%%%%%%%        
//               %%%%%%%%%%%%%%%%%%%%%%%%%%%%       
//                %%%%%%%%%%%%%%%%%%%%%%%%%%%%      
//                  %%%%%%%%%%%%%%%%%%%%%%%%%%%(    
//                   (%%%%%%%%%%%%          #%%%%   
//                     %%%%%%%%%%%%                 
//                      .%%%%%%%%%%/                
//                        %%%%%%%%%%                
//                          %%%%%%%%%               
//                           %%%%%%%%%              
//                            %%%%%%%%             
//                              (%%%%%%.            
//                                %%%%%%            
//                                  %%%%%           
//                                   %%%%%          
//                                     %%%(         
//                                      %%%         
//                                        %%        
//                                         (%       
//                                           %     
pragma solidity ^0.8.13;

import "./ReentrancyGuard.sol";
import "./Ownable.sol";
import "./SafeERC20.sol";

interface IRollers {
    function ownerOf(uint256 tokenId) external view returns (address);
    function addWin(uint256 _rollerId,uint256 _prize) external;
}

enum Stage {
    SecondCommit,
    FirstReveal,
    SecondReveal
}

struct Game {
    uint256 gameId;
    bool opened;
    bool started;
    uint16[2] rollerIds;
    Stage currStage;
    bytes32[2] hashes;
    string[2] commits;
    uint16[30] rolls;
    uint8 stake;
    uint8 winner;
    uint256 deadline;
}

contract deathroll is ReentrancyGuard, Ownable {
    constructor() {
        slotId = 1;
    }

    using SafeERC20 for IERC20;

    modifier isActive (uint256 _gameId) {
        require(games[_gameId].winner==9, "Game has ended");
        _;
    }

    IRollers public ROLLERS;
    IERC20 public MAGIC;
    address private TREASURY;

    mapping (uint256 => uint256) public stakes;
    uint public revealSpan =86400 ;
    uint256 startNum = 10000;
    uint256 treasuryDiv=20;
    bool public opened;

    mapping(uint256 => Game) public games;
    uint256 public slotId;

    event GameCreated(uint256 _gameId,uint256 _rollerId,uint256 _stake);
    event GameJoined(uint256 _gameId, uint256 _rollerId);
    event GameReady(uint256 _gameId,uint256 _winnerId);
    event GameLeft(uint256 _gameId, uint256 _rollerId);

    function createGame(uint256 _rollerId, uint8 _stakeId, uint16 _buddyId, bytes32 _secretWish) external nonReentrant returns(uint256) {
        require(opened, "Cannot create new games at this time");
        uint256 allowance = MAGIC.allowance(msg.sender, address(this));
        require(allowance >= stakes[_stakeId], "Check $MAGIC allowance");
        require(MAGIC.transferFrom(msg.sender,address(this),stakes[_stakeId]), "Not exact amount");

        uint16[2] memory players;
        players[0] = uint8(_rollerId);
        players[1] = _buddyId;
        bytes32[2] memory hashes;
        string[2] memory commits;
        uint16[30] memory rands; 
        Game memory newGame = Game(
            slotId,
            true,
            false,
            players,
            Stage.SecondCommit,
            hashes,
            commits,
            rands,
            _stakeId,
            9,
            0
        );
        newGame.hashes[0] = _secretWish;

        games[slotId] = newGame;
        emit GameCreated(slotId,_rollerId,_stakeId);
        
        slotId++;
    }

    function joinGame( uint256 _rollerId, uint256 _gameId, bytes32 _secretWish) external nonReentrant isActive(_gameId) {
        require(!games[_gameId].started && games[_gameId].opened, "Cannot join this game");
        if(games[_gameId].rollerIds[1]>0){
            require(_rollerId == games[_gameId].rollerIds[1], "This game is private");
        }
        Game storage gameToJoin = games[_gameId];
        require(_rollerId != gameToJoin.rollerIds[0], "Already in this game");
        uint256 allowance = MAGIC.allowance(msg.sender, address(this));
        require(allowance >= stakes[gameToJoin.stake], "Check $MAGIC allowance");
        MAGIC.safeTransferFrom(msg.sender,address(this),stakes[gameToJoin.stake]);

        gameToJoin.rollerIds[1] = uint16(_rollerId);

        gameToJoin.started = true;
        gameToJoin.opened = false;

        gameToJoin.hashes[1] = _secretWish;
        gameToJoin.currStage = Stage.FirstReveal;

        games[_gameId] = gameToJoin;

        emit GameJoined(_gameId,_rollerId);
    }

    function rollTheDice(uint256 _gameId,string memory _wish) external nonReentrant isActive(_gameId) {
        require(games[_gameId].started && !games[_gameId].opened, "Cannot roll this dice");
        Game storage game = games[_gameId];
        require(ROLLERS.ownerOf(game.rollerIds[0])==msg.sender || ROLLERS.ownerOf(game.rollerIds[1])==msg.sender, "You're not in this game");
        require(game.currStage == Stage.FirstReveal || game.currStage == Stage.SecondReveal, "not at reveal stage");

        uint playerIndex;
        if(ROLLERS.ownerOf(game.rollerIds[0]) == msg.sender) playerIndex = 0;
        else if (ROLLERS.ownerOf(game.rollerIds[1]) == msg.sender) playerIndex = 1;
        else revert("unknown player");

        require(keccak256(abi.encodePacked(msg.sender, _wish)) == game.hashes[playerIndex], "invalid hash");

        game.commits[playerIndex] = _wish;

        if(game.currStage == Stage.FirstReveal) {
            game.deadline = block.timestamp + revealSpan;
            require(game.deadline >= block.number, "overflow error");
            game.currStage = Stage.SecondReveal;
        }
        else {
            game.rolls = _getrollsuence(game.commits[0],game.commits[1]);

            uint256 winner;
            if(game.rolls.length % 2 == 0){
                winner=0;
            }else{
                winner=1;
            }
            _reward(game.rollerIds[winner], game.stake);
            game.winner=uint8(winner);
            emit GameReady(_gameId,game.rollerIds[winner]);
        }

        games[_gameId] = game;
    }

    function leaveGame(uint256 _gameId) external nonReentrant isActive(_gameId) {
        Game storage game = games[_gameId];
        require(ROLLERS.ownerOf(game.rollerIds[0])==msg.sender || ROLLERS.ownerOf(game.rollerIds[1])==msg.sender, "You're not in this game");
        if(game.currStage == Stage.SecondCommit){
            MAGIC.safeTransfer(ROLLERS.ownerOf(game.rollerIds[0]),stakes[game.stake]);
            game.winner=uint8(0);
            emit GameLeft(_gameId,game.rollerIds[0]);
        }else if(game.currStage == Stage.SecondReveal){
            bytes memory commitBytes = bytes(game.commits[0]);
            uint256 played = commitBytes.length == 0 ? 1 : 0;
            require(block.timestamp>game.deadline, "Your opponent has not played yet");
            _reward(game.rollerIds[played], game.stake);
            game.winner=uint8(played);
            emit GameLeft(_gameId,game.rollerIds[played]);
        }else{
            revert("You cannot leave the game at this stage");
        }
        games[_gameId] = game;
    }

    function getGameRolls(uint256 _gameId) external view returns(uint16[30] memory){
        return games[_gameId].rolls;
    }

    function getGamePlayers(uint256 _gameId) external view returns(uint256 rollerId0, uint256 rollerId1){
        return (games[_gameId].rollerIds[0],games[_gameId].rollerIds[1]);
    }

    function _reward(uint256 _rollerId, uint256 _stake) internal{
            uint256 prize = (stakes[_stake] * 2);
            uint256 treasury = prize/treasuryDiv;
            MAGIC.transfer(TREASURY,treasury);
            MAGIC.transfer(ROLLERS.ownerOf(_rollerId),prize-treasury);
            ROLLERS.addWin(_rollerId,prize-treasury);
    }

    function _getrollsuence(string memory _seed1,string memory _seed2) internal view returns (uint16[30] memory){
        uint256 div = startNum;
        uint16[30] memory rands; 
        uint256 randomKeccak = uint256(keccak256(abi.encodePacked(_seed1, keccak256(abi.encodePacked(_seed2)))));
        uint256 rollsId=0;

        while(div>1){
            uint256 rand = randomKeccak % div;
            randomKeccak /= div;
            rands[rollsId]=uint16(rand);
            div=rand;
            rollsId++;
        }

        return rands;
    }

    function setStakes(uint256[] memory _stakes) external onlyOwner {
        for(uint i=0;i<_stakes.length;i++){
            stakes[i]= _stakes[i];
        }
    }

    function setAddresses(address _magic, address _rollers, address _treasury) external onlyOwner {
        MAGIC = IERC20(_magic);
        ROLLERS = IRollers(_rollers);
        TREASURY = _treasury;
    }

    function setData(uint256 _startNum, uint256 _newDiv, uint256 _revealSpan) external onlyOwner{
        startNum = _startNum;
        revealSpan=_revealSpan;
        treasuryDiv = _newDiv;
    }

     function setOpened(bool _flag) external onlyOwner{
       opened = _flag;
    }

    
}

