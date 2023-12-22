//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";

import "./MasterOfInflationContracts.sol";

abstract contract MasterOfInflationSettings is Initializable, MasterOfInflationContracts {

    function __MasterOfInflationSettings_init() internal initializer {
        MasterOfInflationContracts.__MasterOfInflationContracts_init();
    }

    function createPool(
        CreatePoolParams calldata _params)
    external
    onlyAdminOrOwner {
        uint64 _poolId = poolId;
        poolId++;

        poolIdToInfo[_poolId].isEnabled = true;
        poolIdToInfo[_poolId].startTime = uint128(block.timestamp);
        poolIdToInfo[_poolId].timeRateLastChanged = poolIdToInfo[_poolId].startTime;
        poolIdToInfo[_poolId].poolCollection = _params.collection;
        poolIdToInfo[_poolId].totalItemsAtLastRateChange = _params.initialItemsInPool;

        emit PoolCreated(_poolId, _params.collection);

        _setItemRatePerSecond(_poolId, _params.itemRatePerSecond, false);
        _setSModifier(_poolId, _params.sModifier);
        _setAdmin(_poolId, _params.admin);
        _setConfigProvider(_poolId, _params.configProvider);
    }

    function setPoolAccess(
        uint64 _poolId,
        SetPoolAccessParams[] calldata _setPoolParams)
    external
    whenNotPaused
    onlyPoolAdmin(_poolId)
    {

        PoolInfo storage _poolInfo = poolIdToInfo[_poolId];

        for(uint256 i = 0; i < _setPoolParams.length; i++) {

            SetPoolAccessParams calldata _params = _setPoolParams[i];

            _poolInfo.addressToAccess[_params.user] = _params.canAccess;

            emit PoolAccessChanged(_poolId, _params.user, _params.canAccess);
        }
    }

    function setItemMintable(
        uint64 _poolId,
        uint256[] calldata _itemIds,
        bool[] calldata _mintables)
    external
    whenNotPaused
    onlyPoolAdmin(_poolId)
    {
        require(_itemIds.length == _mintables.length && _itemIds.length > 0, "Bad array lengths");

        for(uint256 i = 0; i < _itemIds.length; i++) {
            uint256 _itemId = _itemIds[i];
            bool _mintable = _mintables[i];
            poolIdToItemIdToMintable[_poolId][_itemId] = _mintable;

            emit PoolItemMintableChanged(_poolId, _itemId, _mintable);
        }
    }

    function disablePool(
        uint64 _poolId)
    external
    onlyPoolAdmin(_poolId)
    {
        poolIdToInfo[_poolId].isEnabled = false;

        emit PoolDisabled(_poolId);
    }

    function setItemRatePerSecond(
        uint64 _poolId,
        uint256 _itemRate)
    external
    onlyPoolAdmin(_poolId)
    {
        _setItemRatePerSecond(_poolId, _itemRate, true);
    }

    function _setItemRatePerSecond(
        uint64 _poolId,
        uint256 _itemRate,
        bool _updateLastChanged)
    private
    {
        uint256 _oldRate = poolIdToInfo[_poolId].itemRatePerSecond;

        if(_updateLastChanged) {
            uint256 _itemsSinceLastChange = _itemsSinceTime(_oldRate, poolIdToInfo[_poolId].timeRateLastChanged);

            poolIdToInfo[_poolId].totalItemsAtLastRateChange += _itemsSinceLastChange;
            poolIdToInfo[_poolId].timeRateLastChanged = uint128(block.timestamp);
        }

        poolIdToInfo[_poolId].itemRatePerSecond = _itemRate;

        emit PoolRateChanged(_poolId, _oldRate, _itemRate);
    }

    function setSModifier(
        uint64 _poolId,
        uint256 _sModifier)
    external
    onlyPoolAdmin(_poolId)
    {
        _setSModifier(_poolId, _sModifier);
    }

    function _setSModifier(uint64 _poolId, uint256 _sModifier) private {
        uint256 _oldSModifier = poolIdToInfo[_poolId].sModifier;
        poolIdToInfo[_poolId].sModifier = _sModifier;

        emit PoolSModifierChanged(_poolId, _oldSModifier, _sModifier);
    }

    function setAdmin(
        uint64 _poolId,
        address _admin)
    external
    onlyPoolAdmin(_poolId)
    {
        _setAdmin(_poolId, _admin);
    }

    function _setAdmin(uint64 _poolId, address _admin) private {
        require(_admin != address(0), "Cannot set admin to 0");
        address _oldAdmin = poolIdToInfo[_poolId].poolAdmin;
        poolIdToInfo[_poolId].poolAdmin = _admin;

        emit PoolAdminChanged(_poolId, _oldAdmin, _admin);
    }

    function setConfigProvider(
        uint64 _poolId,
        address _configProvider)
    external
    onlyPoolAdmin(_poolId)
    {
        _setConfigProvider(_poolId, _configProvider);
    }

    function _setConfigProvider(uint64 _poolId, address _configProvider) private {
        address _oldConfigProvider = poolIdToInfo[_poolId].poolConfigProvider;
        poolIdToInfo[_poolId].poolConfigProvider = _configProvider;

        emit PoolConfigProviderChanged(_poolId, _oldConfigProvider, _configProvider);
    }

    function itemRatePerSecond(uint64 _poolId)
    external
    view
    validPool(_poolId)
    returns(uint256)
    {
        return poolIdToInfo[_poolId].itemRatePerSecond;
    }

    function _itemsSinceTime(
        uint256 _rate,
        uint128 _timestamp)
    internal
    view
    returns(uint256)
    {
        return ((block.timestamp - _timestamp) * _rate);
    }

    modifier onlyPoolAdmin(uint64 _poolId) {
        require(msg.sender == poolIdToInfo[_poolId].poolAdmin, "Not pool admin");

        _;
    }

    modifier validPool(uint64 _poolId) {
        require(poolIdToInfo[_poolId].isEnabled, "Pool is disabled or does not exist");

        _;
    }

    modifier onlyPoolAccessor(uint64 _poolId) {
        require(poolIdToInfo[_poolId].addressToAccess[msg.sender], "Cannot access pool");

        _;
    }
}

struct CreatePoolParams {
    // Slot 1
    uint256 itemRatePerSecond;
    // Slot 2
    // Should be in ether.
    uint256 initialItemsInPool;
    // Slot 3
    uint256 sModifier;
    // Slot 4 (160/256)
    address admin;
    // Slot 5 (160/256)
    address collection;
    // Slot 6 (160/256)
    address configProvider;
}

struct SetPoolAccessParams {
    // Slot 1 (168/256)
    address user;
    bool canAccess;
}
