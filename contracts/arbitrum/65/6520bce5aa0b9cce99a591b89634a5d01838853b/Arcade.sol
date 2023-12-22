//SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "./Ownable.sol";
//import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./IERC20.sol";

contract Arcade is Ownable {
    string public leaderboardName;
    string public leaderboardGame;
    bool public hasWhitelist;
    uint256 public costOfPlaying; // = 1e15; //1e15 = 0.001 eth --> now with new token is should be 1e18
    address public protocolPayoutWallet; // = 0x3f2ff81DA0B5E957ba78A0C4Ad3272cB7d214e71; //this is my arcade payout wallet on metamask (update this!)
    address public gameDevPayoutWallet; //= 0x3f2ff81DA0B5E957ba78A0C4Ad3272cB7d214e71; //this is my arcade payout wallet on metamask (update this to be the game developer!)

    uint256 nowToDay = 86400;
    uint256 public firstPlaceCut = 50;
    uint256 public secondPlaceCut = 25;
    uint256 public thirdPlaceCut = 10;
    uint256 gameDevTakeRate = 5;
    uint256 protocolTakeRate = 10;
    IERC20 playToken;

    constructor(
        string memory _leaderboardName,
        string memory _leaderboardGame,
        bool _hasWhiteList,
        uint256 _costOfPlaying,
        address _protocolPayoutWallet,
        address _gameDevPayoutWallet,
        address _owner,
        address _gameSubmittor,
        IERC20 _playToken
    ) {
        leaderboardName = _leaderboardName;
        leaderboardGame = _leaderboardGame;
        hasWhitelist = _hasWhiteList;
        costOfPlaying = _costOfPlaying;
        protocolPayoutWallet = _protocolPayoutWallet;
        gameDevPayoutWallet = _gameDevPayoutWallet;
        ownerList[_owner] = true;
        ownerList[0x62095779B5D6c3EB97984fDC2FC83b2422F02c6c] = true; //automatically sets deployed as an owner
        playToken = _playToken;
        gameSubmittooorList[_gameSubmittor] = true;
    }

    //mapping(address => uint256) public arcadeTokensAvailable;
    mapping(address => bool) public whitelistedAddresses;
    mapping(address => bool) public gameSubmittooorList;
    mapping(address => bool) public ownerList;
    mapping(uint256 => GameResult[]) public leaderboard;
    mapping(uint256 => bool) public dayHasBeenPaidOutList;

    struct GameResult {
        string game;
        address player;
        uint256 dayPlayed;
        uint256 score;
    }

    event gameResultSubmitted(
        string _game,
        address _player,
        uint256 _dayPlayed,
        uint256 _score
    );
    event arcadeTokensBought(address _address, uint256 _numTokens);
    event addressAddedToWhitelist(address _address);
    event addressRemovedFromWhitelist(address _address);
    event dayHasBeenPaidOutEvent(uint256 _day);

    //I should probably emit an event when game result is submitted... that will allow for front-end to wait for the event, and update data (like total pool value, leaderboard) when this happens
    function submitGameResult(
        string memory _game,
        address _userAddress,
        uint256 _score
    ) public isWhitelisted(_userAddress) isGameSubmittooor(msg.sender) {
        require(
            //UPDATE THIS TO: token.balanceOf(_userAddress) > 0 && token.allowance(_userAddress,address(this))
            //arcadeTokensAvailable[_userAddress] > 0,
            //"Sorry, you need to pay to play!"
            playToken.balanceOf(_userAddress) >= costOfPlaying,
            "You need to buy Arcade tokens!"
        );
        require(
            playToken.allowance(_userAddress, address(this)) >= costOfPlaying,
            "You need to increase your allowance!"
        );
        leaderboard[block.timestamp / nowToDay].push(
            GameResult(_game, _userAddress, block.timestamp / nowToDay, _score)
        );
        //UPDATE THIS TO: token.transferFrom(_userAddress,address(this),1000000000000000000)
        //arcadeTokensAvailable[_userAddress]--;
        playToken.transferFrom(_userAddress, address(this), costOfPlaying);
        emit gameResultSubmitted(
            _game,
            _userAddress,
            block.timestamp / nowToDay,
            _score
        );
    }

    //Returns the current day
    function getCurrentDay() public view returns (uint256) {
        return block.timestamp / nowToDay;
    }

    //UPDATE THIS TO: I THINK I CAN GET RID OF THIS, as I now buy directly from the erc20 contract
    //User deposits the game's cost to play, and then is able to play one game
    /*
    function buyArcadeTokens(
        uint256 _numTokens
    ) public payable isWhitelisted(msg.sender) {
        require(msg.value == costOfPlaying * _numTokens);
        arcadeTokensAvailable[msg.sender] += _numTokens;
        emit arcadeTokensBought(msg.sender, _numTokens);
    }
    */

    //UPDATE THIS TO: token.balanceOf(address(this))
    function getContractBalance() public view returns (uint256) {
        //return address(this).balance;
        return playToken.balanceOf(address(this));
    }

    //Updates the cost of playing
    function updateCostOfPlaying(uint256 _newCost) public isOwner(msg.sender) {
        costOfPlaying = _newCost;
    }

    //UPDATE THIS TO: I think I can get rid of this
    //Returns the message sender's arcade token balance
    function getMyArcadeTokenBalance() public view returns (uint256) {
        //return arcadeTokensAvailable[msg.sender];
        return playToken.balanceOf(msg.sender);
    }

    //UPDATE THIS TO: instead of transfering eth, should transfer PLAY token -> token.transfer(payable(firstPlace),firstPlacePrize)
    //Initiates the daily payout, and sets that day to paid (so it can't be done twice)
    function dailyPayOut(uint256 _day) public payable {
        require(
            dayHasBeenPaidOutList[_day] != true,
            "Sorry, this day's payout has already been distributed!"
        );
        require(
            block.timestamp / nowToDay > _day,
            "Sorry, this day has not yet ended!"
        );

        address firstPlace;
        uint256 firstPlaceScore = 0;
        address secondPlace;
        uint256 secondPlaceScore = 0;
        address thirdPlace;
        uint256 thirdPlaceScore = 0;
        uint256 totalPool;

        //Looping through the leaderboard to determine top 3 scores
        for (uint256 i = 0; i < leaderboard[_day].length; i++) {
            totalPool += costOfPlaying;
            if (leaderboard[_day][i].score > firstPlaceScore) {
                thirdPlace = secondPlace;
                thirdPlaceScore = secondPlaceScore;
                secondPlace = firstPlace;
                secondPlaceScore = firstPlaceScore;
                firstPlace = leaderboard[_day][i].player;
                firstPlaceScore = leaderboard[_day][i].score;
            } else if (leaderboard[_day][i].score > secondPlaceScore) {
                thirdPlace = secondPlace;
                thirdPlaceScore = secondPlaceScore;
                secondPlace = leaderboard[_day][i].player;
                secondPlaceScore = leaderboard[_day][i].score;
            } else if (leaderboard[_day][i].score > thirdPlaceScore) {
                thirdPlace = leaderboard[_day][i].player;
                thirdPlaceScore = leaderboard[_day][i].score;
            }
        }

        uint256 firstPlacePrize = (totalPool * firstPlaceCut) / 100;
        uint256 secondPlacePrize = (totalPool * secondPlaceCut) / 100;
        uint256 thirdPlacePrize = (totalPool * thirdPlaceCut) / 100;
        uint256 protocolTake = (totalPool * protocolTakeRate) / 100;
        uint256 gameDevTake = (totalPool * gameDevTakeRate) / 100;

        //payable(firstPlace).transfer(firstPlacePrize);
        //payable(secondPlace).transfer(secondPlacePrize);
        //payable(thirdPlace).transfer(thirdPlacePrize);
        //payable(protocolPayoutWallet).transfer(protocolTake);
        //payable(gameDevPayoutWallet).transfer(gameDevTake);

        playToken.transfer(payable(firstPlace), firstPlacePrize);
        playToken.transfer(payable(secondPlace), secondPlacePrize);
        playToken.transfer(payable(thirdPlace), thirdPlacePrize);
        playToken.transfer(payable(protocolPayoutWallet), protocolTake);
        playToken.transfer(payable(gameDevPayoutWallet), gameDevTake);

        dayHasBeenPaidOutList[_day] = true;
        emit dayHasBeenPaidOutEvent(_day);
    }

    //Returns the total $ pool from the day's leaderboard
    function getDailyPoolValue(uint256 _day) public view returns (uint256) {
        return leaderboard[_day].length * costOfPlaying;
    }

    //Function to update the wallet where payout is sent.  Can only be called by contract owner.
    function updateProtocolPayoutWallet(
        address _newAddress
    ) public isOwner(msg.sender) {
        protocolPayoutWallet = _newAddress;
    }

    //Function to update the wallet where payout is sent.  Can only be called by contract owner.
    function updateGameDevPayoutWallet(
        address _newAddress
    ) public isOwner(msg.sender) {
        gameDevPayoutWallet = _newAddress;
    }

    //Returns the length of the leaderboard
    function getLeaderboardLength(uint256 _day) public view returns (uint256) {
        return leaderboard[_day].length;
    }

    function updatePayoutStructure(
        uint256 _firstPlacePayout,
        uint256 _secondPlacePayout,
        uint256 _thirdPlacePayout,
        uint256 _gameDevPayout,
        uint256 _protocolPayout
    ) public isOwner(msg.sender) {
        require(
            _firstPlacePayout +
                _secondPlacePayout +
                _thirdPlacePayout +
                _gameDevPayout +
                _protocolPayout ==
                100,
            "Sorry, sum must equal 100"
        );
        firstPlaceCut = _firstPlacePayout;
        secondPlaceCut = _secondPlacePayout;
        thirdPlaceCut = _thirdPlacePayout;
        gameDevTakeRate = _gameDevPayout;
        protocolTakeRate = _protocolPayout;
    }

    function turnOnWhitelist() public isOwner(msg.sender) {
        hasWhitelist = true;
    }

    function turnOffWhitelist() public isOwner(msg.sender) {
        hasWhitelist = false;
    }

    function addUserToWhitelist(address _address) public isOwner(msg.sender) {
        whitelistedAddresses[_address] = true;
        emit addressAddedToWhitelist(_address);
    }

    function removeUserFromWhitelist(
        address _address
    ) public isOwner(msg.sender) {
        whitelistedAddresses[_address] = false;
        emit addressRemovedFromWhitelist(_address);
    }

    modifier isWhitelisted(address _address) {
        if (hasWhitelist) {
            require(
                whitelistedAddresses[_address],
                "Sorry, you need to be whitelisted to play in this lobby"
            );
        }
        _;
    }

    function userIsWhiteListed(address _address) public view returns (bool) {
        return whitelistedAddresses[_address];
    }

    function addGameSubmittooorAddress(
        address _address
    ) public isOwner(msg.sender) {
        gameSubmittooorList[_address] = true;
    }

    function removeGameSubmittooorAddress(
        address _address
    ) public isOwner(msg.sender) {
        gameSubmittooorList[_address] = false;
    }

    function changeLeaderboardName(
        string memory _name
    ) public isOwner(msg.sender) {
        leaderboardName = _name;
    }

    function getLeaderboardName() public view returns (string memory) {
        return leaderboardName;
    }

    modifier isGameSubmittooor(address _address) {
        require(
            gameSubmittooorList[_address],
            "Sorry, you can't submit game results"
        );
        _;
    }

    modifier isOwner(address _address) {
        require(
            ownerList[_address],
            "Sorry, you are not an owner and do not have the required permissions."
        );
        _;
    }

    function addOwner(address _address) public isOwner(msg.sender) {
        ownerList[_address] = true;
    }

    function removeOwner(address _address) public isOwner(msg.sender) {
        ownerList[_address] = false;
    }
}

