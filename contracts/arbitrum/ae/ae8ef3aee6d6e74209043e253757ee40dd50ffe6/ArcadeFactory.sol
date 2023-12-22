// File: contracts/Context.sol


// OpenZeppelin Contracts v4.4.1 (utils/Context.sol)

pragma solidity ^0.8.0;

/**
 * @dev Provides information about the current execution context, including the
 * sender of the transaction and its data. While these are generally available
 * via msg.sender and msg.data, they should not be accessed in such a direct
 * manner, since when dealing with meta-transactions the account sending and
 * paying for execution may not be the actual sender (as far as an application
 * is concerned).
 *
 * This contract is only required for intermediate, library-like contracts.
 */
abstract contract Context {
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes calldata) {
        return msg.data;
    }
}
// File: contracts/Ownable.sol


// OpenZeppelin Contracts v4.4.1 (access/Ownable.sol)

pragma solidity ^0.8.0;


/**
 * @dev Contract module which provides a basic access control mechanism, where
 * there is an account (an owner) that can be granted exclusive access to
 * specific functions.
 *
 * By default, the owner account will be the one that deploys the contract. This
 * can later be changed with {transferOwnership}.
 *
 * This module is used through inheritance. It will make available the modifier
 * `onlyOwner`, which can be applied to your functions to restrict their use to
 * the owner.
 */
abstract contract Ownable is Context {
    address private _owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /**
     * @dev Initializes the contract setting the deployer as the initial owner.
     */
    constructor() {
        _transferOwnership(_msgSender());
    }

    /**
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyOwner() {
        _checkOwner();
        _;
    }

    /**
     * @dev Returns the address of the current owner.
     */
    function owner() public view virtual returns (address) {
        return _owner;
    }

    /**
     * @dev Throws if the sender is not the owner.
     */
    function _checkOwner() internal view virtual {
        require(owner() == _msgSender(), "Ownable: caller is not the owner");
    }

    /**
     * @dev Leaves the contract without owner. It will not be possible to call
     * `onlyOwner` functions anymore. Can only be called by the current owner.
     *
     * NOTE: Renouncing ownership will leave the contract without an owner,
     * thereby removing any functionality that is only available to the owner.
     */
    function renounceOwnership() public virtual onlyOwner {
        _transferOwnership(address(0));
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Can only be called by the current owner.
     */
    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        _transferOwnership(newOwner);
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Internal function without access restriction.
     */
    function _transferOwnership(address newOwner) internal virtual {
        address oldOwner = _owner;
        _owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }
}
// File: contracts/Arcade.sol

pragma solidity ^0.8.7;


contract Arcade is Ownable {
    string public leaderboardName;
    string public leaderboardGame;
    bool public hasWhitelist;
    uint256 public costOfPlaying; // = 1e15; //1e15 = 0.001 eth
    address public protocolPayoutWallet; // = 0x3f2ff81DA0B5E957ba78A0C4Ad3272cB7d214e71; //this is my arcade payout wallet on metamask (update this!)
    address public gameDevPayoutWallet; //= 0x3f2ff81DA0B5E957ba78A0C4Ad3272cB7d214e71; //this is my arcade payout wallet on metamask (update this to be the game developer!)

    uint256 nowToDay = 86400;
    uint256 public firstPlaceCut = 50;
    uint256 public secondPlaceCut = 25;
    uint256 public thirdPlaceCut = 10;
    uint256 gameDevTakeRate = 5;
    uint256 protocolTakeRate = 10;

    constructor(
        string memory _leaderboardName,
        string memory _leaderboardGame,
        bool _hasWhiteList,
        uint256 _costOfPlaying,
        address _protocolPayoutWallet,
        address _gameDevPayoutWallet,
        address _owner
    ) {
        leaderboardName = _leaderboardName;
        leaderboardGame = _leaderboardGame;
        hasWhitelist = _hasWhiteList;
        costOfPlaying = _costOfPlaying;
        protocolPayoutWallet = _protocolPayoutWallet;
        gameDevPayoutWallet = _gameDevPayoutWallet;
        ownerList[_owner] = true;
    }

    mapping(address => uint256) public arcadeTokensAvailable;
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
            arcadeTokensAvailable[_userAddress] > 0,
            "Sorry, you need to pay to play!"
        );
        leaderboard[block.timestamp / nowToDay].push(
            GameResult(_game, _userAddress, block.timestamp / nowToDay, _score)
        );
        arcadeTokensAvailable[_userAddress]--;
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

    //User deposits the game's cost to play, and then is able to play one game
    function buyArcadeTokens(
        uint256 _numTokens
    ) public payable isWhitelisted(msg.sender) {
        require(msg.value == costOfPlaying * _numTokens);
        arcadeTokensAvailable[msg.sender] += _numTokens;
        emit arcadeTokensBought(msg.sender, _numTokens);
    }

    //I think I can get rid of this
    function getContractBalance() public view returns (uint256) {
        return address(this).balance;
    }

    //Updates the cost of playing
    function updateCostOfPlaying(uint256 _newCost) public isOwner(msg.sender) {
        costOfPlaying = _newCost;
    }

    //Returns the message sender's arcade token balance
    function getMyArcadeTokenBalance() public view returns (uint256) {
        return arcadeTokensAvailable[msg.sender];
    }

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

        payable(firstPlace).transfer(firstPlacePrize);
        payable(secondPlace).transfer(secondPlacePrize);
        payable(thirdPlace).transfer(thirdPlacePrize);
        payable(protocolPayoutWallet).transfer(protocolTake);
        payable(gameDevPayoutWallet).transfer(gameDevTake);
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

// File: contracts/ArcadeFactory.sol

pragma solidity ^0.8.7;



contract ArcadeFactory is Ownable {
    Arcade[] public arcades;

    function createArcade(
        string memory _leaderboardName,
        string memory _leaderboardGame,
        bool _hasWhiteList,
        uint256 _costOfPlaying,
        address _protocolPayoutWallet,
        address _gameDevPayoutWallet
    ) public onlyOwner {
        Arcade arcade = new Arcade(
            _leaderboardName,
            _leaderboardGame,
            _hasWhiteList,
            _costOfPlaying,
            _protocolPayoutWallet,
            _gameDevPayoutWallet,
            msg.sender
        );
        arcades.push(arcade);
    }

    function getAllArcades() public view returns(Arcade[] memory arcade){
        return arcades;
    }
}

//Lobby0, Pong, false, 1000000000000000, 0xAb8483F64d9C6d1EcF9b849Ae677dD3315835cb2,0xAb8483F64d9C6d1EcF9b849Ae677dD3315835cb2