//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";

import "./IERC1155Mintable.sol";

import "./MasterOfInflationSettings.sol";

contract MasterOfInflation is Initializable, MasterOfInflationSettings {

    function initialize() external initializer {
        MasterOfInflationSettings.__MasterOfInflationSettings_init();
    }

    function tryMintFromPool(
        MintFromPoolParams calldata _params)
    external
    validPool(_params.poolId)
    onlyPoolAccessor(_params.poolId)
    returns(bool _didMintItem)
    {
        require(poolIdToItemIdToMintable[_params.poolId][_params.itemId], "Item not mintable");

        // 1. Calculate odds of getting the item
        uint256 _chanceOfItem = chanceOfItemFromPool(_params.poolId, _params.amount, _params.bonus);

        // 2. Roll dice
        if(_chanceOfItem > 0) {
            uint256 _rollResult = _params.randomNumber % 100000;
            if(_rollResult < _chanceOfItem) {
                _didMintItem = true;
            }
        }

        // 3. Mint if needed
        if(_didMintItem) {
            IERC1155Mintable(poolIdToInfo[_params.poolId].poolCollection).mint(
                _params.user,
                _params.itemId,
                _params.amount
            );

            poolIdToInfo[_params.poolId].itemsClaimed += (_params.amount * 1 ether);

            emit ItemMintedFromPool(
                _params.poolId,
                _params.user,
                _params.itemId,
                _params.amount);
        }
    }

    // Returns a number of 100,000 indicating the chance of pulling an item from this pool
    //
    function chanceOfItemFromPool(uint64 _poolId, uint64 _amount, uint32 _bonus) public view returns(uint256) {
        uint256 _itemsInPool = itemsInPool(_poolId);

        // Don't have enough to give this amount
        //
        if(_itemsInPool < _amount * 1 ether) {
            return 0;
        }

        IPoolConfigProvider _configProvider = IPoolConfigProvider(poolIdToInfo[_poolId].poolConfigProvider);

        uint256 _n = _configProvider.getN(_poolId);

        // Function is 1/(1 + (N/k * s)^2). Because solidity has no decimals, we need
        // to use `ether` to indicate decimals.

        uint256 _baseOdds = 10**25 / (10**20 + (((_n * 10**28) / _itemsInPool) * ((poolIdToInfo[_poolId].sModifier * 10**5) / 100000))**2);

        return (_baseOdds * (1 ether + (10**13 * uint256(_bonus)))) / 1 ether;
    }

    function itemsInPool(uint64 _poolId) public view returns(uint256) {
        PoolInfo storage _poolInfo = poolIdToInfo[_poolId];

        return _poolInfo.totalItemsAtLastRateChange
            + _itemsSinceTime(_poolInfo.itemRatePerSecond, _poolInfo.timeRateLastChanged)
            - _poolInfo.itemsClaimed;
    }

    function hasAccessToPool(uint64 _poolId, address _address) external view returns(bool) {
        return poolIdToInfo[_poolId].addressToAccess[_address];
    }
}
