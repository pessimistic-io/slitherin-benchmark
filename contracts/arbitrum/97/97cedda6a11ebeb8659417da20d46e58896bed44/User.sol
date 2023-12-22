/***************************************************************************************************
// This contract defines a User of the DAO eco-system
// The users can be different people who interact with the dao contracts through their
// respective end-user applications(Eg: A patron, bar-tender, bar-admin, etc.)
// Once the user registers on the app, it should create a profile for the user on the blockchain
// using this contract
***************************************************************************************************/
// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.12;

import "./Constants.sol";
import "./StringUtils.sol";
import "./IUser.sol";
import "./DAOAccessControlled.sol";

import "./Counters.sol";
import "./Initializable.sol";

contract User is IUser,Initializable, DAOAccessControlled {
    using Counters for Counters.Counter;

    // An incremental unique Id that identifies a user
    Counters.Counter private userIds;

    // A list of all registered users
    address[] public allUsers;

    // Protocol-wide banlist
    mapping(address => bool) public bannedUsers;

    // User wallet address => User Attributes
    // This maps unique user Ids to users details
    mapping(address => UserAttributes) public userAttributes;

    function initialize(address _authority) public initializer {
        DAOAccessControlled._setAuthority(_authority); 
        userIds.increment(); // Start from 1 as id == 0 is a check for existence
    }

    /**
     * @notice              Registers the caller as a new user. Only application calls must be accepted.
     * @param   _name       User name
     * @param   _walletAddress  User avatar URI
     * @param   _avatarURI    Data URI for the user's avatar
     * @param   _dataURI    Data URI for the user
     * @return  _           User ID
     */
    function register(
        string memory _name,
        address _walletAddress,
        string memory _avatarURI,
        string memory _dataURI
    ) external onlyDispatcher returns (uint256) {
        return _createUser(_name, _walletAddress, _avatarURI, _dataURI);
    }

    /**
     * @notice Allows a user to set their display name
     * @param _name string Name
    */
    function changeName(string memory _name) external {
        require(userAttributes[_msgSender()].id != 0, "NON EXISTENT");
        uint256 len = StringUtils.strlen(_name);
        require(len >= Constants.MIN_NAME_LENGTH && len <= Constants.MAX_NAME_LENGTH, "Name length out of range");
        
        userAttributes[_msgSender()].name = _name;
        emit NameChanged(_msgSender(), _name);
    }

    /**
     * @notice Update AvatarURI from mobile app.
     * @param _avatarURI string AvatarURI
    */
    function setAvatarURI(string memory _avatarURI) external onlyForwarder {
        require(userAttributes[_msgSender()].id != 0, "NON EXISTENT");

        userAttributes[_msgSender()].avatarURI = _avatarURI;
        emit AvatarURIChanged(_msgSender(), _avatarURI);
    }

    /**
     * @notice Update DataURI from mobile app.
     * @param _dataURI string Data URI
    */
    function setDataURI(string memory _dataURI) external onlyForwarder {
        require(userAttributes[_msgSender()].id != 0, "NON EXISTENT");

        userAttributes[_msgSender()].dataURI = _dataURI;
        emit DataURIChanged(_msgSender(), _dataURI);
    }

    /**
     * @notice          Puts a user on ban list
     * @param   _user   A user to ban
     */
    function ban(address _user) external onlyPolicy {
        require(!bannedUsers[_user], "Already banned");
   
        bannedUsers[_user] = true;
        emit Banned(_user);
    }

    /**
     * @notice          Lifts user ban
     * @param   _user   A user to lift the ban
     */
    function liftBan(address _user) external onlyPolicy {
        require(bannedUsers[_user], "Not banned");
        
        bannedUsers[_user] = false;        
        emit BanLifted(_user);
    }

    function getAllUsers(bool _includeBanned) external view returns(UserAttributes[] memory _users) {
        if (_includeBanned) {
            _users = new UserAttributes[](allUsers.length);
            for (uint256 i = 0; i < allUsers.length; i++) {
                _users[i] = userAttributes[allUsers[i]];
            }
        } else {
            uint count;
            for (uint256 i = 0; i < allUsers.length; i++) {
                if (!bannedUsers[allUsers[i]]) {
                    count++;
                }
            }

            _users = new UserAttributes[](count);
            uint256 idx;
            for (uint256 i = 0; i < allUsers.length; i++) {
                if (!bannedUsers[allUsers[i]] ) {
                    _users[idx] = userAttributes[allUsers[i]];
                    idx++;
                }
            }
        }
    }

    /**
     * @notice      Returns a list of banned users
     */
    function getBannedUsers() external view returns(UserAttributes[] memory _users) {
        uint count;
        for (uint256 i = 0; i < allUsers.length; i++) {
            if (bannedUsers[allUsers[i]]) {
                count++;
            }
        }

        _users = new UserAttributes[](count);
        uint256 idx;
        for (uint256 i = 0; i < allUsers.length; i++) {
            if (bannedUsers[allUsers[i]] ) {
                _users[idx] = userAttributes[allUsers[i]];
                idx++;
            }
        }  
    }

    /**
     * @notice Creates a user with the given name, avatar and wallet Address
     * @notice Newly created users are added to a list and stored in this contracts storage
     * @notice A mapping maps each user ID to their details
     * @notice The application can use the list and mapping to get relevant details about the user
     * @param _name string Name of the user
     * @param _walletAddress address Wallet address of the user
     * @param _avatarURI string Avatar URI of the user
     * @param _dataURI string Data URI of the user
     * @return userId_ User ID for newly created user
    */
    function _createUser(
        string memory _name,
        address _walletAddress,
        string memory _avatarURI,
        string memory _dataURI
    ) internal returns (uint256 userId_) {
        require(_walletAddress != address(0), "Wallet address needed");
        require(userAttributes[_walletAddress].id == 0, "User already exists");
        uint256 len = StringUtils.strlen(_name);
        require(len >= Constants.MIN_NAME_LENGTH && len <= Constants.MAX_NAME_LENGTH, "Name length out of range");
        require(StringUtils.strlen(_avatarURI) <= Constants.MAX_URI_LENGTH, "Avatar URI too long");
        require(StringUtils.strlen(_dataURI) <= Constants.MAX_URI_LENGTH, "Data URI too long");

        // Assign a unique ID to the new user to be created
        userId_ = userIds.current();
        
        // Set details for the user and add them to the mapping
        userAttributes[_walletAddress] = UserAttributes({
            id: userId_,
            name: _name,
            wallet: _walletAddress,
            avatarURI: _avatarURI,
            dataURI: _dataURI
        });

        // Add the new user to list of users
        allUsers.push(_walletAddress);

        // Increment ID for next user
        userIds.increment();

        // Emit an event for user creation with details
        emit UserCreated(_walletAddress, userId_, _name);
    }
} 
