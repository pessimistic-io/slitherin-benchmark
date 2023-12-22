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
import "./DAOAccessControlled.sol";

import "./IUser.sol";
import "./ILoot8SignatureVerification.sol";

import "./Counters.sol";
import "./Initializable.sol";

contract User is IUser, Initializable, DAOAccessControlled {
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

    struct LinkedExternalAccounts {
        address account;
        bytes signature;
        uint nonce;
    }

    // Mapping Users Loot8 wallet address => Linked external wallet addresses
    mapping(address => LinkedExternalAccounts[]) public linkedExternalAccounts;

    string public linkMessage;

    address public verifier;

    function initialize(address _authority) public initializer {
        DAOAccessControlled._setAuthority(_authority); 
        userIds.increment(); // Start from 1 as id == 0 is a check for existence
    }

    function initializer2(address _verifier) public reinitializer(2) {
        verifier = _verifier;
        linkMessage = 'Link this Account to Loot8';
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

    function deregister() external {
        require(userAttributes[_msgSender()].id != 0, "NON EXISTENT USER");
        uint256 userCount = allUsers.length;
        address lastUser = allUsers[userCount - 1];
        for(uint256 i = 0; i < userCount; i++) {
            address user = allUsers[i];
            if(user == _msgSender()) {
                if(i < userCount-1) {
                    allUsers[i] = lastUser;
                }
                allUsers.pop();
                delete userAttributes[_msgSender()];
                delete linkedExternalAccounts[_msgSender()];
                break;
            }
        }

        emit UserRemoved(_msgSender());

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

    function getAllUsers(bool _includeBanned) public view returns(UserAttributes[] memory _users) {
        if (_includeBanned) {
            _users = new UserAttributes[](allUsers.length);
            for (uint256 i = 0; i < allUsers.length; i++) {
                _users[i] = userAttributes[allUsers[i]];
            }
        } else {
            uint256 count;
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
        uint256 count;
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
     * @notice Checks is an address is a registered user 
     * @notice of the application and not banned
     * @param _user address Wallet address of the user
     * @return bool true if valid user false if invalid
    */
    function isValidPermittedUser(address _user) public view returns(bool) {
        
        if(userAttributes[_user].id > 0 && !bannedUsers[_user]) {
            return true;
        }

        return false;
    }

    /**
     * @notice Adds entity to lists for holding positions held
     * @notice by user at different entities
     * @param _user address Wallet address of the user
     * @param _entity address Entity contract address
     * @param _admin bool Entity added to admin list if true else to bartender list
    */
    function addEntityToOperatorsList(address _user, address _entity, bool _admin) external {
        
        require(_msgSender() == _entity, "UNAUTHORIZED");
        
        (bool isOperator,) = isUserOperatorAt(_user, _entity, _admin);

        if(isOperator) {
            return;
        } else if(_admin) {
            userAttributes[_user].adminAt.push(_entity);
        } else {
            userAttributes[_user].bartenderAt.push(_entity);
        }
        
    }

    /**
     * @notice Removes entity from lists for holding positions held
     * @notice by user at different entities
     * @param _user address Wallet address of the user
     * @param _entity address Entity contract address
     * @param _admin bool Entity removed from admin list if true else from bartender list
    */
    function removeEntityFromOperatorsList(address _user, address _entity, bool _admin) external {
        
        require(_msgSender() == _entity, "UNAUTHORIZED");

        (bool isOperator, uint256 index) = isUserOperatorAt(_user, _entity, _admin);

        if(!isOperator) {
            return;
        } else if(_admin) {
            userAttributes[_user].adminAt[index] = userAttributes[_user].adminAt[userAttributes[_user].adminAt.length - 1];
            userAttributes[_user].adminAt.pop();
        } else {
            userAttributes[_user].bartenderAt[index] = userAttributes[_user].bartenderAt[userAttributes[_user].bartenderAt.length - 1];
            userAttributes[_user].bartenderAt.pop();
        }
        
    }

    /**
     * @notice Checks if a user is an operator at a specific entity
     * @param _user address Wallet address of the user
     * @param _entity address Entity contract address
     * @param _admin bool Checks admin list if true else bartender list
     * @return (bool, uint256) Tuple representing if user is operator and index of entity in list
    */
    function isUserOperatorAt(address _user, address _entity, bool _admin) public view returns(bool, uint256) {
        
        address[] memory operatorList;

        if(_admin) {
            operatorList = userAttributes[_user].adminAt;
        } else {
            operatorList = userAttributes[_user].bartenderAt;
        }

        for(uint256 i = 0; i < operatorList.length; i++) {
            if(userAttributes[_user].adminAt[i] == _entity) {
                return(true, i);
            }
        }

        return(false, 0);

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
        uint256[20] memory __gap;
        require(len >= Constants.MIN_NAME_LENGTH && len <= Constants.MAX_NAME_LENGTH, "Name length out of range");
        require(StringUtils.strlen(_avatarURI) <= Constants.MAX_URI_LENGTH, "Avatar URI too long");
        require(StringUtils.strlen(_dataURI) <= Constants.MAX_URI_LENGTH, "Data URI too long");

        // Assign a unique ID to the new user to be created
        userId_ = userIds.current();

        address[] memory _initList;
        // Set details for the user and add them to the mapping
        userAttributes[_walletAddress] = UserAttributes({
            id: userId_,
            name: _name,
            wallet: _walletAddress,
            avatarURI: _avatarURI,
            dataURI: _dataURI,
            adminAt: _initList,
            bartenderAt: _initList,
            __gap: __gap
        });

        // Add the new user to list of users
        allUsers.push(_walletAddress);

        // Increment ID for next user
        userIds.increment();

        // Emit an event for user creation with details
        emit UserCreated(_walletAddress, userId_, _name);
    }

    function linkExternalAccount(address _account, bytes memory _signature) external {
        
        address user = _msgSender();
        require(isValidPermittedUser(user), "UNAUTHORIZED");
        require(!isLinkedAccount(user, _account), "ACCOUNT IS ALREADY LINKED");
    
        ILoot8SignatureVerification verifierContract = ILoot8SignatureVerification(verifier);

        uint256 nonce = verifierContract.getSignerCurrentNonce(_account);

        require(verifierContract.verifyAndUpdateNonce(
            _account,
            user,
            linkMessage,
            _signature
        ), "INVALID SIGNATURE");

        linkedExternalAccounts[user].push(LinkedExternalAccounts({
            account: _account,
            signature: _signature,
            nonce: nonce
        }));

        emit LinkedExternalAccountForUser(user, _account);
    }

    function delinkExternalAccount(address _account) external {
        
        address user = _msgSender();
        require(isValidPermittedUser(user), "UNAUTHORIZED");
        
        for(uint256 i = 0; i < linkedExternalAccounts[user].length; i++) {
            if(linkedExternalAccounts[user][i].account == _account) {
                if(i < linkedExternalAccounts[user].length) {
                    linkedExternalAccounts[user][i] = linkedExternalAccounts[user][linkedExternalAccounts[user].length - 1];
                }
                linkedExternalAccounts[user].pop();
                emit DeLinkedExternalAccountForUser(user, _account);
                break;
            }
        }
    }

    function isLinkedAccount(address _user, address _account) public view returns(bool) {

        for(uint256 i = 0; i < linkedExternalAccounts[_user].length; i++) {
            if(linkedExternalAccounts[_user][i].account == _account) {
                return true;
            }
        }

        return false;
    }

    function getLinkedAccountForUser(address _user) public view returns(LinkedExternalAccounts[] memory linkedAccounts) {
        linkedAccounts = new LinkedExternalAccounts[](linkedExternalAccounts[_user].length);
        for(uint256 i = 0; i < linkedExternalAccounts[_user].length; i++) {
            linkedAccounts[i] = linkedExternalAccounts[_user][i];
        }
    }
} 
