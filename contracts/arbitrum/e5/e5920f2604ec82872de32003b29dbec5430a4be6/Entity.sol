/**************************************************************************************************************
    This is an administrative contract for entities(brands, establishments or partners)
    in the DAO eco-system. The contract is spinned up by the DAO Governor using the Entity Factory.
    An Entity Admin is set up on each contract to perform managerial tasks for the entity.
**************************************************************************************************************/
// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import "./DAOAccessControlled.sol";
import "./IEntity.sol";
import "./IDAOAuthority.sol";
import "./ICollectible.sol";

import "./Strings.sol";
import "./Counters.sol";
import "./Initializable.sol";

contract Entity is IEntity, Initializable, DAOAccessControlled {

    using Counters for Counters.Counter;

    // Unique Ids for Operator
    Counters.Counter private operatorIds;  

    // Details for the entity
    EntityData entityData;

    // Area where the entity is located
    Area public area;
    
    // List of all admins for this entity
    address[] public entityAdmins;

    // List of all bartenders for this entity
    address[] public bartenders;

    // List of whitelisted third-party collectible contracts 
    ContractDetails[] public whitelistedCollectibles;

    // (address => chainId => index) 1-based index lookup for third-party collectibles whitelisting/delisting
    mapping( address => mapping( uint256 => uint256 ) ) public whitelistedCollectiblesLookup;

    // Blacklisted patrons
    mapping( address => BlacklistDetails ) public blacklist;

    // Entity Admin Address => Entity Admin Details
    mapping( address => Operator ) public entityAdminDetails;

    // Bartender Address => Bartender Details
    mapping( address => Operator ) public bartenderDetails;
    
    function initialize(
        Area memory _area,
        string memory _name,
        string memory _dataURI,
        address _walletAddress,
        address _authority
    ) public initializer {
        DAOAccessControlled._setAuthority(_authority);
        area = _area;
        entityData.name = _name;
        entityData.dataURI = _dataURI;
        entityData.walletAddress = _walletAddress;
        entityData.isActive = true;

        operatorIds.increment(); // Start from 1 as 0 is used for existence check
    }

    /**
     * @notice Allows the DAO administration to enable/disable an entity.
     * @notice When an entity is disabled all collectibles for the given entity are also retired.
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
    function updateEntityDataURI(string memory _dataURI) external onlyEntityAdmin(address(this)) {
        string memory olddataURI = entityData.dataURI;
        entityData.dataURI = _dataURI;
        emit EntityDataURIUpdated(olddataURI, entityData.dataURI);
    }

    /**
     * @notice Grants entity admin role for an entity to a given wallet address
     * @param _entAdmin address wallet address of the entity admin
    */
    function addEntityAdmin(address _entAdmin) external onlyGovernor {

        // Admin cannot be zero address
        require(_entAdmin != address(0), "ZERO ADDRESS");

        // Check if address already an entity admin
        require(entityAdminDetails[_entAdmin].id == 0, "ADDRESS ALREADY ADMIN FOR ENTITY");

        // Add entity admin to list of admins
        entityAdmins.push(_entAdmin);

        // Set details for the entity admin
        // Data Loc for admin details: dataURI, "/admins/" , adminId
        uint256[5] memory __gap;
        entityAdminDetails[_entAdmin] = Operator({
            id: operatorIds.current(),
            isActive: true,
            __gap: __gap
        });

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

        // Check if address already an entity admin
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

        // Emit event to signal toggling of entity admin role
        emit EntityAdminToggled(address(this), _entAdmin, _status);
    }

    function toggleBartender(address _bartender) external onlyEntityAdmin(address(this)) returns(bool _status) {
        
        require(bartenderDetails[_bartender].id != 0, "No such bartender for this entity");

        bartenderDetails[_bartender].isActive = !bartenderDetails[_bartender].isActive;

        // Poll status to pass as return value
        _status = bartenderDetails[_bartender].isActive;

        // Emit event to signal toggling of bartender role
        emit BartenderToggled(address(this), _bartender, _status);
    }

    function getEntityAdminDetails(address _entAdmin) public view returns(Operator memory) {
        return entityAdminDetails[_entAdmin];
    }

    function getBartenderDetails(address _bartender) public view returns(Operator memory) {
        return bartenderDetails[_bartender];
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

    /**
     * @notice          add an address to third-party collectibles whitelist
     * @param _source   collectible contract address
     * @param _chainId  chainId where contract is deployed
     */
    function whitelistCollectible(address _source, uint256 _chainId) onlyEntityAdmin(address(this)) external {
        uint256 index = whitelistedCollectiblesLookup[_source][_chainId];
        require(index == 0, "Collectible already whitelisted");

        uint256[5] memory __gap;
        whitelistedCollectibles.push(ContractDetails({
            source: _source,
            chainId: _chainId,
            __gap: __gap
        }));

        whitelistedCollectiblesLookup[_source][_chainId] = whitelistedCollectibles.length; // store as 1-based index
        emit CollectibleWhitelisted(address(this), _source, _chainId);
    }

    /**
     * @notice          remove an address from third-party collectibles whitelist
     * @param _source   collectible contract address
     * @param _chainId  chainId where contract is deployed
     */
    function delistCollectible(address _source, uint256 _chainId) onlyEntityAdmin(address(this)) external {
        uint256 index = whitelistedCollectiblesLookup[_source][_chainId];
        require(index > 0, "Collectible is not whitelisted");

        delete whitelistedCollectibles[index - 1]; // convert to 0-based index
        delete whitelistedCollectiblesLookup[_source][_chainId];

        emit CollectibleDelisted(address(this), _source, _chainId);
    }

    function getEntityData() public view returns(EntityData memory) {
        return entityData;
    }

    function getAllEntityAdmins() public view returns(address[] memory) {
        return entityAdmins;
    }

    function getAllBartenders() public view returns(address[] memory) {
        return bartenders;
    }

    
    function getAllWhitelistedCollectibles() public view returns(ContractDetails[] memory) {
        return whitelistedCollectibles;
    }

    function getLocationDetails() external view returns(string[] memory, uint256) {
        return (area.points, area.radius);
    }
}
