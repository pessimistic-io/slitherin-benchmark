// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

interface IUser {

    /* ========== EVENTS ========== */
    event UserCreated(address indexed _walletAddress, uint256 indexed _userId, string _name);
    event UserRemoved(address indexed _walletAddress);

    event NameChanged(address indexed _user, string _name);
    event AvatarURIChanged(address indexed _user, string _avatarURI);
    event DataURIChanged(address indexed _user, string _dataURI);

    event Banned(address indexed _user);
    event BanLifted(address indexed _user);

    struct UserAttributes {
        uint256 id;
        string name;
        address wallet;
        string avatarURI;
        string dataURI;
        address[] adminAt; // List of entities where user is an Admin
        address[] bartenderAt; // List of entities where user is a bartender

        // Storage Gap
        uint256[20] __gap;
    }

    function register(string memory _name, address walletAddress, string memory _avatarURI, string memory _dataURI) external returns (uint256);

    function deregister() external;

    function changeName(string memory _name) external;
    
    function getAllUsers(bool _includeBanned) external view returns(UserAttributes[] memory _users);

    function getBannedUsers() external view returns(UserAttributes[] memory _users);

    function isValidPermittedUser(address _user) external view returns(bool);

    function addEntityToOperatorsList(address _user, address _entity, bool _admin) external;

    function removeEntityFromOperatorsList(address _user, address _entity, bool _admin) external;

    function isUserOperatorAt(address _user, address _entity, bool _admin) external view returns(bool, uint256);

}
