// SPDX-License-Identifier: MIT

pragma solidity =0.8.4;

import { IAbstractVault as IOriginAbstractVault } from "./IAbstractVault.sol";
import { IBaseReward as IOriginBaseReward } from "./IBaseReward.sol";
import { IStorageAddresses } from "./IStorageAddresses.sol";

interface IAbstractVault is IOriginAbstractVault {
    function creditManagers(uint256 _index) external view returns (address);

    function creditManagersCount() external view returns (uint256);
}

interface IBaseReward is IOriginBaseReward {
    function totalSupply() external view returns (uint256);
}

contract VaultInfo {
    bool private _initializing;

    modifier initializer() {
        require(!_initializing, "VaultInfo: Contract is already initialized");
        _;
    }

    // @notice used to initialize the contract
    function initialize() external initializer {
        _initializing = true;
    }

    function workingBalance(address[] calldata _vaults) public view returns (address[] memory, uint256[] memory) {
        address[] memory underlyingTokens = new address[](_vaults.length);
        uint256[] memory total = new uint256[](_vaults.length);

        for (uint256 i = 0; i < _vaults.length; i++) {
            address supplyRewardPool = IAbstractVault(_vaults[i]).supplyRewardPool();
            underlyingTokens[i] = IAbstractVault(_vaults[i]).underlyingToken();
            total[i] = IBaseReward(supplyRewardPool).totalSupply();
        }

        return (underlyingTokens, total);
    }

    function borrowedBalance(address[] calldata _vaults) public view returns (address[] memory, uint256[] memory) {
        address[] memory underlyingTokens = new address[](_vaults.length);
        uint256[] memory total = new uint256[](_vaults.length);

        for (uint256 i = 0; i < _vaults.length; i++) {
            address[] memory borrowedRewardPools = new address[](IAbstractVault(_vaults[i]).creditManagersCount());

            for (uint256 j = 0; j < IAbstractVault(_vaults[i]).creditManagersCount(); j++) {
                address creditManager = IAbstractVault(_vaults[i]).creditManagers(j);
                address borrowedRewardPool = IAbstractVault(_vaults[i]).borrowedRewardPool(creditManager);

                if (!_findIndex(borrowedRewardPools, borrowedRewardPool)) {
                    borrowedRewardPools[j] = borrowedRewardPool;
                    total[i] += IBaseReward(borrowedRewardPool).totalSupply();
                }
            }

            underlyingTokens[i] = IAbstractVault(_vaults[i]).underlyingToken();
        }

        return (underlyingTokens, total);
    }

    function lockedBalance(address[] calldata _vaults) public view returns (address[] memory, uint256[] memory) {
        address[] memory underlyingTokens = new address[](_vaults.length);
        uint256[] memory total = new uint256[](_vaults.length);

        for (uint256 i = 0; i < _vaults.length; i++) {
            address[] memory borrowedRewardPools = new address[](IAbstractVault(_vaults[i]).creditManagersCount());

            for (uint256 j = 0; j < IAbstractVault(_vaults[i]).creditManagersCount(); j++) {
                address creditManager = IAbstractVault(_vaults[i]).creditManagers(j);
                address borrowedRewardPool = IAbstractVault(_vaults[i]).borrowedRewardPool(creditManager);
                address shareLocker = IAbstractVault(_vaults[i]).creditManagersShareLocker(creditManager);

                if (!_findIndex(borrowedRewardPools, borrowedRewardPool)) {
                    borrowedRewardPools[j] = borrowedRewardPool;
                    total[i] += IBaseReward(borrowedRewardPool).balanceOf(shareLocker);
                }
            }

            underlyingTokens[i] = IAbstractVault(_vaults[i]).underlyingToken();
        }

        return (underlyingTokens, total);
    }

    function _findIndex(address[] memory array, address element) internal pure returns (bool found) {
        for (uint256 i = 0; i < array.length; i++) {
            if (array[i] == element) {
                found = true;
                break;
            }
        }
    }
}

