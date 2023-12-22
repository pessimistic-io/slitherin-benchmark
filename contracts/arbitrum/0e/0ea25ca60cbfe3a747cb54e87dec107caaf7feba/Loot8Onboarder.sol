// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import "./DAOAccessControlled.sol";

import "./IUser.sol";
import "./ILoot8Onboarder.sol";
import "./IEntityFactory.sol";

import "./Initializable.sol";

contract Loot8Onboarder is ILoot8Onboarder, Initializable, DAOAccessControlled {
    
    // Stores valid invite codes for onboarding
    mapping(bytes32 => bool) public inviteHashes;

    // Codes redemption info
    mapping(bytes32 => bool) public redeemed;
    
    address public userContract;
    address public entityFactory;

    event EntityFactoryUpdated(address _entityFactory, address _newEntityFactory);

    // Flag to mark a user as onboarded
    mapping(address => bool) public userOnboarded;

    // Number of invite codes sent by user to others
    mapping(address => uint256) public invitesSent;

    function initialize(
        address _authority,
        address _userContract,
        address _entityFactory
    ) public initializer {
        DAOAccessControlled._setAuthority(_authority);
        userContract = _userContract;
        entityFactory = _entityFactory;
    }

    function addInviteHash(bytes32[] memory _hashedCode) external {
        
        address governor = authority.getAuthorities().governor;
        address msgSender = _msgSender();

        require(
            msgSender == governor ||
            (
                IUser(userContract).isValidPermittedUser(msgSender) &&
                userOnboarded[msgSender]
            ), 
            "UNAUTHORIZED"
        );

        for (uint256 i = 0; i < _hashedCode.length; i++) {
            if (msgSender != governor) {
                require(invitesSent[msgSender] <= 5, "INVITE LIMIT BREACHED");
                invitesSent[msgSender]++;
            }
            require(!inviteHashes[_hashedCode[i]], "DUPLICATE CODE");
            inviteHashes[_hashedCode[i]] = true;
        }
    }

    function _isValidCode(string memory _inviteCode) internal view returns(bool) {
        bytes32 hashedCode = keccak256(abi.encode(_inviteCode));
        return inviteHashes[hashedCode];
    }

    function _isRedeemedCode(string memory _inviteCode) internal view returns(bool) {
        bytes32 hashedCode = keccak256(abi.encode(_inviteCode));
        return redeemed[hashedCode];
    }
    
    function onboard(string memory _inviteCode, bytes memory _creationData) public returns(address _entity) {
        require(_isValidCode(_inviteCode), "INVALID CODE");
        require(!_isRedeemedCode(_inviteCode), "REDEEMED CODE");

        require(IUser(userContract).isValidPermittedUser(_msgSender()), "UNAUTHORIZED");
        require(!userOnboarded[_msgSender()], "USER IS ALREADY ONBOARDED");

        // Create Entity
        _entity = IEntityFactory(entityFactory).createEntity(_creationData);

        // Add message sender as entity admin for the new entity
        IEntity(_entity).addEntityAdmin(_msgSender());

        // Mark inviteCode as redeemed
        redeemed[keccak256(abi.encode(_inviteCode))] = true;

        userOnboarded[_msgSender()] = true;

        emit EntityOnboarded(_inviteCode, _entity);
    }

    function setEntityFactory(address _newEntityFactory) external onlyGovernor {
        address oldEntityFactory = entityFactory;
        entityFactory = _newEntityFactory;
        emit EntityFactoryUpdated(oldEntityFactory, entityFactory);
    }
}
