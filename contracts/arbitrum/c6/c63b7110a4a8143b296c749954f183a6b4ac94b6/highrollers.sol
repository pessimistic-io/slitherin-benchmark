pragma solidity ^0.8.13;

import "./ReentrancyGuard.sol";
import "./Ownable.sol";
import "./ERC721Enumerable.sol";
import "./Strings.sol";

interface IFriend{
    function ownerOf(uint256 tokenId) external returns(address);
}

contract highrollers is Ownable {
    constructor() {
        mintCounter=1;
    }

    modifier isAuth(){
        require(authorized[msg.sender],"Not authorized");
        _;
    }

    using Strings for uint256;

    uint256 private mintCounter;
    mapping (uint256 => uint256) public victories;
    mapping (uint256 => uint256) public highestWin;
    mapping (uint256 => uint256) public totalWon;
    mapping (address => bool) public authorized;
    mapping (address => bool) public authFriends;
    mapping (address => mapping (uint256 => uint256)) public rollerId;
    mapping (uint256 => address) public rollToFriends;
    mapping (uint256 => uint256) public rollToFriendId;

    bool public  paused;


    function checkOwnership(address _toCheck, uint256 _friendId, address _friendAddress) external returns (uint256 _rollerId) {
        require(!paused, "Roll room is full! (for now)");
        require(authFriends[_friendAddress], "These friends haven't been added yet!");
        require(IFriend(_friendAddress).ownerOf(_friendId)==_toCheck, "You don't own this friend!");
        if(rollerId[_friendAddress][_friendId]==0){
            rollerId[_friendAddress][_friendId]=mintCounter;
            rollToFriends[mintCounter]=_friendAddress;
            rollToFriendId[mintCounter]=_friendId;
            mintCounter++;
        }
        return rollerId[_friendAddress][_friendId];
    }

    function getOwner(uint256 _rollerId) external returns (address){
        return IFriend(rollToFriends[_rollerId]).ownerOf(rollToFriendId[_rollerId]);
    }

    function addWin(uint256 _rollerId,uint256 _prize) external isAuth {
        victories[_rollerId]++;
        totalWon[_rollerId]+=_prize;
        if(_prize>highestWin[_rollerId]) highestWin[_rollerId]=_prize;
    }

    function getRoller(uint256 _rollerId) external view returns(uint256,uint256,uint256,address,uint256){
        return (victories[_rollerId],highestWin[_rollerId],totalWon[_rollerId],rollToFriends[_rollerId],rollToFriendId[_rollerId]);
    }

    function setAuthorized(address _address, bool _flag) external onlyOwner {
        authorized[_address]=_flag;
    }

    function addFriends(address _friendsAddress,bool _flag) external onlyOwner{
        authFriends[_friendsAddress]=_flag;
    }

    function pause(bool _flag) external onlyOwner{
        paused = _flag;
    }
}
