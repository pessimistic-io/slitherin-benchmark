/**************************************************************************************************************
    This is an administrative contract for entities(brands, establishments or partners)
    in the DAO eco-system. The contract is spinned up by the DAO Governor using the Entity Factory.
    An Entity Admin is set up on each contract to perform managerial tasks for the entity.
**************************************************************************************************************/
// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import "./DAOAccessControlled.sol";
import "./IEntity.sol";
import "./IUser.sol";
import "./IDAOAuthority.sol";

import "./Counters.sol";
import "./Initializable.sol";

contract Entity is IEntity, Initializable, DAOAccessControlled {

    using Counters for Counters.Counter;

    // Unique Ids for Operator
    Counters.Counter private operatorIds;  

    // Details for the entity
    EntityData public entityData;

    // Area where the entity is located
    Area public area;

    // Contract for registered users
    address public userContract;
    
    // List of all admins for this entity
    address[] public entityAdmins;

    // List of all bartenders for this entity
    address[] public bartenders;

    // Blacklisted patrons
    mapping( address => BlacklistDetails ) public blacklist;

    // Entity Admin Address => Entity Admin Details
    mapping( address => Operator ) public entityAdminDetails;

    // Bartender Address => Bartender Details
    mapping( address => Operator ) public bartenderDetails;
    
    address public onboarder;

    // Added an onboarder in addition to initializeV1 params
    function initializeV2(
        Area memory _area,
        string memory _name,
        string memory _dataURI,
        address _walletAddress,
        address _authority,
        address _userContract,
        address _onboarder
    ) public initializer {

        DAOAccessControlled._setAuthority(_authority);
        userContract = _userContract;
        area = _area;
        entityData.name = _name;
        entityData.dataURI = _dataURI;
        entityData.walletAddress = _walletAddress;
        entityData.isActive = true;
        onboarder = _onboarder;
        operatorIds.increment(); // Start from 1 as 0 is used for existence check
    }

    /**
     * @notice Allows the DAO administration to enable/disable an entity.
     * @notice When an entity is disabled all collections for the given entity are also retired.
     * @notice Enabling the same entity back again will need configuration of new Collectibles.
     * @return _status boolean Status after toggling
    */
    function toggleEntity() external onlyGovernor returns(bool _status) {

        // Activates/deactivates the entity
        entityData.isActive = !entityData.isActive;

        // Poll status to pass as return value
        _status = entityData.isActive;

        // Emit an entity toggling event with relevant details
        emit EntityToggled(address(this), _status);
    }

    /**
     * @notice Allows DAO Operator to modify the data for an entity
     * @notice Entity area, wallet address and ipfs location can be modified
     * @param _area Area Address of the entity
     * @param _name string Name of the entity
     * @param _dataURI string DataURI for the entity
     * @param _walletAddress address Wallet address for the entity
    */
    function updateEntity(
        Area memory _area,
        string memory _name,
        string memory _dataURI,
        address _walletAddress
    ) external onlyGovernor {

        area = _area;
        entityData.name = _name;
        entityData.dataURI = _dataURI;
        entityData.walletAddress = _walletAddress;

        // Emit an event for entity updation with the relevant details
        emit EntityUpdated(address(this), _area, _dataURI, _walletAddress);
    }

    /**
     * @notice Allows Entity Admin to modify the dataURI for an entity
     * @param _dataURI string DataURI for the entity
    */
    function updateDataURI(string memory _dataURI) external onlyEntityAdmin(address(this)) {
        string memory olddataURI = entityData.dataURI;
        entityData.dataURI = _dataURI;
        emit EntityDataURIUpdated(olddataURI, entityData.dataURI);
    }

    /**
     * @notice Grants entity admin role for an entity to a given wallet address
     * @param _entAdmin address wallet address of the entity admin
    */
    function addEntityAdmin(address _entAdmin) external {

        require(
            _msgSender() == authority.getAuthorities().governor ||
            _msgSender() == onboarder,
            "UNAUTHORIZED"
        );

        // Admin cannot be zero address
        require(_entAdmin != address(0), "ZERO ADDRESS");

        // _entAdmin should be a valid user of the application
        require(IUser(userContract).isValidPermittedUser(_entAdmin), "INVALID OR BANNED USER");

        // Check if address already an entity admin
        require(entityAdminDetails[_entAdmin].id == 0, "ADDRESS ALREADY ADMIN FOR ENTITY");

        // Add entity admin to list of admins
        entityAdmins.push(_entAdmin);

        // Set details for the entity admin
        uint256[5] memory __gap;
        entityAdminDetails[_entAdmin] = Operator({
            id: operatorIds.current(),
            isActive: true,
            __gap: __gap
        });

        // Add entity to users admin lists
        IUser(userContract).addEntityToOperatorsList(_entAdmin, address(this), true);

        // Increment the Id for next admin addition
        operatorIds.increment();

        // Emit event to signal grant of entity admin role to an address
        emit EntityAdminGranted(address(this), _entAdmin);
    }

    /**
     * @notice Grants bartender role for an entity to a given wallet address
     * @param _bartender address Wallet address of the bartender
    */
    function addBartender(address _bartender) external onlyEntityAdmin(address(this)) {
        
        // Bartender cannot be zero address
        require(_bartender != address(0), "ZERO ADDRESS");

        // _bartender should be a valid user of the application
        require(IUser(userContract).isValidPermittedUser(_bartender), "INVALID OR BANNED USER");

        // Check if address already a bartender
        require(bartenderDetails[_bartender].id == 0, "ADDRESS ALREADY BARTENDER FOR ENTITY");

        // Add bartender to list of bartenders
        bartenders.push(_bartender);

        // Set details for the bartender
        // Data Loc for admin details: dataURI, "/admins/" , adminId
        uint256[5] memory __gap;
        bartenderDetails[_bartender] = Operator({
            id: operatorIds.current(),
            isActive: true,
            __gap: __gap
        });

        // Add entity to users admin lists
        IUser(userContract).addEntityToOperatorsList(_bartender, address(this), false);

        // Increment the Id for next admin addition
        operatorIds.increment();

        // Emit event to signal grant of bartender role to an address
        emit BartenderGranted(address(this), _bartender);
    }

    function toggleEntityAdmin(address _entAdmin) external onlyGovernor returns(bool _status) {

        require(entityAdminDetails[_entAdmin].id != 0, "No such entity admin for this entity");
    
        entityAdminDetails[_entAdmin].isActive = !entityAdminDetails[_entAdmin].isActive;

        // Poll status to pass as return value
        _status = entityAdminDetails[_entAdmin].isActive;

        if(_status) {
            // Add entity to users admin lists
            IUser(userContract).addEntityToOperatorsList(_entAdmin, address(this), true);
        } else {
            // Remove entity from users admin lists
            IUser(userContract).removeEntityFromOperatorsList(_entAdmin, address(this), true);
        }

        // Emit event to signal toggling of entity admin role
        emit EntityAdminToggled(address(this), _entAdmin, _status);
    }

    function toggleBartender(address _bartender) external onlyEntityAdmin(address(this)) returns(bool _status) {
        
        require(bartenderDetails[_bartender].id != 0, "No such bartender for this entity");

        bartenderDetails[_bartender].isActive = !bartenderDetails[_bartender].isActive;

        // Poll status to pass as return value
        _status = bartenderDetails[_bartender].isActive;

        if(_status) {
            // Add entity to users admin lists
            IUser(userContract).addEntityToOperatorsList(_bartender, address(this), false);
        } else {
            // Remove entity from users admin lists
            IUser(userContract).removeEntityFromOperatorsList(_bartender, address(this), false);
        }

        // Emit event to signal toggling of bartender role
        emit BartenderToggled(address(this), _bartender, _status);
    }

    function addPatronToBlacklist(address _patron, uint256 _end) external onlyEntityAdmin(address(this)) {
        uint256[5] memory __gap;
        blacklist[_patron] = BlacklistDetails({
            end: _end,
            __gap: __gap
        });
    }

    function removePatronFromBlacklist(address _patron) external onlyEntityAdmin(address(this)) {
        require(blacklist[_patron].end > 0, "Patron not blacklisted");
        blacklist[_patron].end = 0;
    }

    function getEntityData() public view returns(EntityData memory) {
        return entityData;
    }

    function getEntityAdminDetails(address _entAdmin) public view returns(Operator memory) {
        return entityAdminDetails[_entAdmin];
    }

    function getBartenderDetails(address _bartender) public view returns(Operator memory) {
        return bartenderDetails[_bartender];
    }

    function getAllEntityAdmins(bool _onlyActive) public view returns(address[] memory _entAdmins) {
        if(_onlyActive) {

            uint count;
            for (uint256 i = 0; i < entityAdmins.length; i++) {
                if (entityAdminDetails[entityAdmins[i]].isActive) {
                    count++;
                }
            }
            
            _entAdmins = new address[](count);
            uint256 _idx;
            for(uint256 i=0; i < entityAdmins.length; i++) {
                if(entityAdminDetails[entityAdmins[i]].isActive) {
                    _entAdmins[_idx] = entityAdmins[i];
                    _idx++;
                }
            }
        } else {
            _entAdmins = entityAdmins;
        }
    }

    function getAllBartenders(bool _onlyActive) public view returns(address[] memory _bartenders) {
        if(_onlyActive) {

            uint count;
            for (uint256 i = 0; i < bartenders.length; i++) {
                if (bartenderDetails[bartenders[i]].isActive) {
                    count++;
                }
            }
            
            _bartenders = new address[](count);
            uint256 _idx;
            for(uint256 i=0; i < bartenders.length; i++) {
                if(bartenderDetails[bartenders[i]].isActive) {
                    _bartenders[_idx] = bartenders[i];
                    _idx++;
                }
            }
        } else {
            _bartenders = bartenders;
        }
    }

    function getLocationDetails() external view returns(string[] memory, uint256) {
        return (area.points, area.radius);
    }

    /**
     * @notice Allows the administrator to change user contract for Entity Operation
     * @param _newUserContract address
    */
    function setUserContract(address _newUserContract) external onlyGovernor {
        userContract = _newUserContract;

        emit UserContractSet(_newUserContract);
    }
}
