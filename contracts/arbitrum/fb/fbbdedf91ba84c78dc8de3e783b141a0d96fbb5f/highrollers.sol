pragma solidity ^0.8.13;

import "./ReentrancyGuard.sol";
import "./Ownable.sol";
import "./ERC721Enumerable.sol";
import "./Strings.sol";

interface IFriend{
    function ownerOf(uint256 tokenId) external returns(address);
}

contract highrollers is ERC721Enumerable, ReentrancyGuard, Ownable {
    constructor() ERC721("Highrollers", "ROLLERS") {}

    modifier isAuth(){
        require(authorized[msg.sender],"Not authorized");
        _;
    }

    using Strings for uint256;

    uint256 private mintCounter;
    mapping (uint256 => string) public names;
    mapping (uint256 => uint256) public victories;
    mapping (uint256 => uint256) public highestWin;
    mapping (uint256 => uint256) public totalWon;
    mapping (address => bool) public authorized;
    mapping (address => bool) public authFriends;
    mapping (address => mapping (uint256 => bool)) public exists;
    mapping (uint256 => address) public rollToFriends;
    mapping (uint256 => uint256) public rollToFriendId;

    string public BASE_URI;
    bool public  paused;
    bool public isFreeRoll;

    event Roll(string name, address friendAddress, uint256 friendId);
    event FreeRoll(string name);

    function roll(string memory _name, address _friendAddress, uint256 _friendId) external nonReentrant {
        require(!paused, "Roll room is full! (for now)");
        require(authFriends[_friendAddress], "These friends haven't been added yet!");
        require(IFriend(_friendAddress).ownerOf(_friendId)==msg.sender, "You don't own this friend");
        require(!exists[_friendAddress][_friendId], "This Roller already exists");
        _mint(msg.sender,mintCounter);  
        rollToFriends[mintCounter]=_friendAddress;
        rollToFriendId[mintCounter]=_friendId;
        names[mintCounter] = _name;
        mintCounter++;
        exists[_friendAddress][_friendId]=true;

        emit Roll(_name,_friendAddress,_friendId);
    }

    function freeRoll(string memory _name) external nonReentrant {
        require(!paused && isFreeRoll, "Roll room is full! (for now)");
        _mint(msg.sender,mintCounter);  
        names[mintCounter] = _name;
        mintCounter++;

        emit FreeRoll(_name);
    }

    function addWin(uint256 _rollerId,uint256 _prize) external isAuth {
        victories[_rollerId]++;
        totalWon[_rollerId]+=_prize;
        if(_prize>highestWin[_rollerId]) highestWin[_rollerId]=_prize;
    }

    function tokenURI(uint256 _rollId)
        public
        view
        virtual
        override
        returns (string memory)
    {
        require(_exists(_rollId));
        return
            string(
                abi.encodePacked(
                    BASE_URI,
                    _rollId.toString()
                )
            );
    }

    function getRoller(uint256 _rollerId) external view returns(string memory, uint256,uint256,uint256,address,uint256){
        return (names[_rollerId],victories[_rollerId],highestWin[_rollerId],totalWon[_rollerId],rollToFriends[_rollerId],rollToFriendId[_rollerId]);
    }

    function setAuthorized(address _address, bool _flag) external onlyOwner {
        authorized[_address]=_flag;
    }

     function setURI(string memory _uri) external onlyOwner {
        BASE_URI = _uri;
    }

    function addFriends(address _friendsAddress,bool _flag) external onlyOwner{
        authFriends[_friendsAddress]=_flag;
    }

    function pause(bool _flag, bool _freeRoll) external onlyOwner{
        paused = _flag;
        isFreeRoll = _freeRoll;
    }
}
