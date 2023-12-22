pragma solidity ^0.8.0;
// Copyright 2022 Nevermined AG.

// SPDX-License-Identifier: (Apache-2.0 AND CC-BY-4.0)
// Code is Apache-2.0 and docs are CC-BY-4.0


import "./EpochLibrary.sol";
import "./ConditionStoreLibrary.sol";
import "./INVMConfig.sol";
import "./OwnableUpgradeable.sol";
import "./AccessControlUpgradeable.sol";
import "./IExternalRegistry.sol";
import "./Common.sol";

/**
 * @title Condition Store Manager
 * @author Nevermined
 *
 * @dev Implementation of the Condition Store Manager.
 *
 *      Condition store manager is responsible for enforcing the 
 *      the business logic behind creating/updating the condition state
 *      based on the assigned role to each party. Only specific type of
 *      contracts are allowed to call this contract, therefore there are 
 *      two types of roles, create role that in which is able to create conditions.
 *      The second role is the update role, which is can update the condition state.
 *      Also, it support delegating the roles to other contract(s)/account(s).
 */
contract ConditionStoreManager is CommonAccessControl {

    bytes32 private constant PROXY_ROLE = keccak256('PROXY_ROLE');

    using ConditionStoreLibrary for ConditionStoreLibrary.ConditionList;
    using EpochLibrary for EpochLibrary.EpochList;

    enum RoleType { Create, Update }
    address private createRole;
    ConditionStoreLibrary.ConditionList internal conditionList;
    EpochLibrary.EpochList internal epochList;

    address internal nvmConfigAddress;

    IExternalRegistry public didRegistry;
    
    event ConditionCreated(
        bytes32 indexed _id,
        address indexed _typeRef,
        address indexed _who
    );

    event ConditionUpdated(
        bytes32 indexed _id,
        address indexed _typeRef,
        ConditionStoreLibrary.ConditionState indexed _state,
        address _who
    );

    modifier onlyCreateRole(){
        require(
            createRole == _msgSender(),
            'Invalid CreateRole'
        );
        _;
    }

    modifier onlyUpdateRole(bytes32 _id)
    {
        require(
            conditionList.conditions[_id].typeRef != address(0),
            'Condition doesnt exist'
        );
        require(
            conditionList.conditions[_id].typeRef == _msgSender(),
            'Invalid UpdateRole'
        );
        _;
    }

    modifier onlyValidType(address typeRef)
    {
        require(
            typeRef != address(0),
            'Invalid address'
        );
        require(AddressUpgradeable.isContract(typeRef), 'Invalid contract address');
        _;
    }

   /**
    * @notice create creates new Epoch
    * @param _self is the Epoch storage pointer
    * @param _timeLock value in block count (can not fulfill before)
    * @param _timeOut value in block count (can not fulfill after)
    */
    function createEpoch(
        EpochLibrary.EpochList storage _self,
        bytes32 _id,
        uint256 _timeLock,
        uint256 _timeOut
    )
        internal
    {
        require(
            _self.epochs[_id].blockNumber == 0,
            'Id already exists'
        );

        require(
            _timeLock + block.number >= block.number &&
            _timeOut + block.number >= block.number,
            'Indicating integer overflow/underflow'
        );

        if (_timeOut > 0 && _timeLock > 0) {
            require(
                _timeLock < _timeOut,
                'Invalid time margin'
            );
        }

        _self.epochs[_id] = EpochLibrary.Epoch({
            timeLock : _timeLock,
            timeOut : _timeOut,
            blockNumber : block.number
        });

    }


    /**
     * @dev initialize ConditionStoreManager Initializer
     *      Initialize Ownable. Only on contract creation,
     * @param _creator refers to the creator of the contract
     * @param _owner refers to the owner of the contract           
     * @param _nvmConfigAddress refers to the contract address of `NeverminedConfig`
     */
    function initialize(
        address _creator,
        address _owner,
        address _nvmConfigAddress
    )
        public
        initializer
    {
        require(
            _owner != address(0),
            'Invalid address'
        );
        require(
            createRole == address(0),
            'Role already assigned'
        );

        require(
            _nvmConfigAddress != address(0), 
                'Invalid Address'
        );
        
        OwnableUpgradeable.__Ownable_init();
        transferOwnership(_owner);
        createRole = _creator;
        _setupRole(DEFAULT_ADMIN_ROLE, _owner);
        
        nvmConfigAddress= _nvmConfigAddress;
    }

    /**
     * @dev Set provenance registry
     * @param _didAddress did registry address. can be zero
     */
    function setProvenanceRegistry(address _didAddress) public {
        didRegistry = IExternalRegistry(_didAddress);
    }

    /**
     * @dev getCreateRole get the address of contract
     *      which has the create role
     * @return create condition role address
     */
    function getCreateRole()
        external
        view
        returns (address)
    {
        return createRole;
    }

    /**
     * @dev getNvmConfigAddress get the address of the NeverminedConfig contract
     * @return NeverminedConfig contract address
     */
    function getNvmConfigAddress()
    public
    override
    view
    returns (address)
    {
        return nvmConfigAddress;
    }    
    
    function setNvmConfigAddress(address _addr)
    external
    onlyOwner
    {
        nvmConfigAddress = _addr;
    }
    
    /**
     * @dev delegateCreateRole only owner can delegate the 
     *      create condition role to a different address
     * @param delegatee delegatee address
     */
    function delegateCreateRole(
        address delegatee
    )
        external
        onlyOwner()
    {
        require(
            delegatee != address(0),
            'Invalid delegatee address'
        );
        createRole = delegatee;
    }

    /**
     * @dev delegateUpdateRole only owner can delegate 
     *      the update role to a different address for 
     *      specific condition Id which has the create role
     * @param delegatee delegatee address
     */
    function delegateUpdateRole(
        bytes32 _id,
        address delegatee
    )
        external
        onlyOwner()
    {
        require(
            delegatee != address(0),
            'Invalid delegatee address'
        );
        require(
            conditionList.conditions[_id].typeRef != address(0),
            'Invalid condition Id'
        );
        conditionList.conditions[_id].typeRef = delegatee;
    }

    function grantProxyRole(address _address) public onlyOwner {
        grantRole(PROXY_ROLE, _address);
    }

    function revokeProxyRole(address _address) public onlyOwner {
        revokeRole(PROXY_ROLE, _address);
    }

    /**
     * @dev createCondition only called by create role address 
     *      the condition should use a valid condition contract 
     *      address, valid time lock and timeout. Moreover, it 
     *      enforce the condition state transition from 
     *      Uninitialized to Unfulfilled.
     * @param _id unique condition identifier
     * @param _typeRef condition contract address
     */
    function createCondition(
        bytes32 _id,
        address _typeRef
    )
    external
    {
        createCondition(
            _id,
            _typeRef,
            uint(0),
            uint(0)
        );
    }
    
    function createCondition2(
        bytes32 _id,
        address _typeRef
    )
    external
    {
        createCondition(
            _id,
            _typeRef,
            uint(0),
            uint(0)
        );
    }
    
    /**
     * @dev createCondition only called by create role address 
     *      the condition should use a valid condition contract 
     *      address, valid time lock and timeout. Moreover, it 
     *      enforce the condition state transition from 
     *      Uninitialized to Unfulfilled.
     * @param _id unique condition identifier
     * @param _typeRef condition contract address
     * @param _timeLock start of the time window
     * @param _timeOut end of the time window
     */
    function createCondition(
        bytes32 _id,
        address _typeRef,
        uint _timeLock,
        uint _timeOut
    )
        public
        onlyCreateRole
        onlyValidType(_typeRef)
    {
        createEpoch(epochList, _id, _timeLock, _timeOut);

        conditionList.create(_id, _typeRef);

        emit ConditionCreated(
            _id,
            _typeRef,
            _msgSender()
        );
    }

    /**
     * @dev updateConditionState only called by update role address. 
     *      It enforce the condition state transition to either 
     *      Fulfill or Aborted state
     * @param _id unique condition identifier
     * @return the current condition state 
     */
    function updateConditionState(
        bytes32 _id,
        ConditionStoreLibrary.ConditionState _newState
    )
        external
        onlyUpdateRole(_id)
        returns (ConditionStoreLibrary.ConditionState)
    {
        return _updateConditionState(_id, _newState);
    }

    function _updateConditionState(
        bytes32 _id,
        ConditionStoreLibrary.ConditionState _newState
    )
        internal
        returns (ConditionStoreLibrary.ConditionState)
    {
        // no update before time lock
        require(
            !isConditionTimeLocked(_id),
            'TimeLock is not over yet'
        );

        ConditionStoreLibrary.ConditionState updateState = _newState;

        // auto abort after time out
        if (isConditionTimedOut(_id)) {
            updateState = ConditionStoreLibrary.ConditionState.Aborted;
        }

        conditionList.updateState(_id, updateState);

        emit ConditionUpdated(
            _id,
            conditionList.conditions[_id].typeRef,
            updateState,
            _msgSender()
        );

        return updateState;
    }

    function updateConditionStateWithProvenance(
        bytes32 _id,
        bytes32 _did,
        string memory name,
        address user,
        ConditionStoreLibrary.ConditionState _newState
    )
        external
        onlyUpdateRole(_id)
        returns (ConditionStoreLibrary.ConditionState)
    {
        ConditionStoreLibrary.ConditionState state = _updateConditionState(_id, _newState);
        if (address(didRegistry) != address(0)) {
            didRegistry.used(_id, _did, user, keccak256(bytes(name)), '', name);
        }
        
        return state;
    }

    function updateConditionMapping(
        bytes32 _id,
        bytes32 _key,
        bytes32 _value
    )
    external
    onlyUpdateRole(_id)
    {
        conditionList.updateKeyValue(
            _id, 
            _key, 
            _value
        );
    }
    
    function updateConditionMappingProxy(
        bytes32 _id,
        bytes32 _key,
        bytes32 _value
    )
    external
    {
        require(hasRole(PROXY_ROLE, _msgSender()) || hasNVMOperatorRole(_msgSender()), 'Invalid access role');
        conditionList.updateKeyValue(
            _id, 
            _key, 
            _value
        );
    }
    
    /**
     * @dev getCondition  
     * @return typeRef the type reference
     * @return state condition state
     * @return timeLock the time lock
     * @return timeOut time out
     * @return blockNumber block number
     */
    function getCondition(bytes32 _id)
        external
        view
        returns (
            address typeRef,
            ConditionStoreLibrary.ConditionState state,
            uint timeLock,
            uint timeOut,
            uint blockNumber
        )
    {
        typeRef = conditionList.conditions[_id].typeRef;
        state = conditionList.conditions[_id].state;
        timeLock = epochList.epochs[_id].timeLock;
        timeOut = epochList.epochs[_id].timeOut;
        blockNumber = epochList.epochs[_id].blockNumber;
    }

    /**
     * @dev getConditionState  
     * @return condition state
     */
    function getConditionState(bytes32 _id)
        external
        view
        virtual
        returns (ConditionStoreLibrary.ConditionState)
    {
        return conditionList.conditions[_id].state;
    }

    /**
     * @dev getConditionTypeRef  
     * @return condition typeRef
     */
    function getConditionTypeRef(bytes32 _id)
    external
    view
    virtual
    returns (address)
    {
        return conditionList.conditions[_id].typeRef;
    }    

    /**
     * @dev getConditionState  
     * @return condition state
     */
    function getMappingValue(bytes32 _id, bytes32 _key)
    external
    view
    virtual
    returns (bytes32)
    {
        return conditionList.map[_id][_key];
    }    

    /**
     * @dev isConditionTimeLocked  
     * @return whether the condition is timedLock ended
     */
    function isConditionTimeLocked(bytes32 _id)
        public
        view
        returns (bool)
    {
        return epochList.isTimeLocked(_id);
    }

    /**
     * @dev isConditionTimedOut  
     * @return whether the condition is timed out 
     */
    function isConditionTimedOut(bytes32 _id)
        public
        view
        returns (bool)
    {
        return epochList.isTimedOut(_id);
    }
}

