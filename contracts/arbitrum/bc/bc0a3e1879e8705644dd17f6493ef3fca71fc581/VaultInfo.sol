// SPDX-License-Identifier: MIT

pragma solidity =0.8.4;

import { IAbstractVault as IOriginAbstractVault } from "./IAbstractVault.sol";
import { IBaseReward as IOriginBaseReward } from "./IBaseReward.sol";

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
            address borrowedRewardPool = IAbstractVault(_vaults[i]).borrowedRewardPool();

            underlyingTokens[i] = IAbstractVault(_vaults[i]).underlyingToken();
            total[i] = IBaseReward(borrowedRewardPool).totalSupply();
        }

        return (underlyingTokens, total);
    }

    function lockedBalance(address[] calldata _vaults) public view returns (address[] memory, uint256[] memory) {
        address[] memory underlyingTokens = new address[](_vaults.length);
        uint256[] memory total = new uint256[](_vaults.length);

        for (uint256 i = 0; i < _vaults.length; i++) {
            address borrowedRewardPool = IAbstractVault(_vaults[i]).borrowedRewardPool();

            underlyingTokens[i] = IAbstractVault(_vaults[i]).underlyingToken();

            for (uint256 j = 0; j < IAbstractVault(_vaults[i]).creditManagersCount(); j++) {
                address creditManager = IAbstractVault(_vaults[i]).creditManagers(j);
                address shareLocker = IAbstractVault(_vaults[i]).creditManagersShareLocker(creditManager);

                total[i] += IBaseReward(borrowedRewardPool).balanceOf(shareLocker);
            }
        }

        return (underlyingTokens, total);
    }

    function debtBalance(address[] calldata _vaults) public view returns (address[] memory, uint256[] memory) {
        address[] memory underlyingTokens = new address[](_vaults.length);
        uint256[] memory total = new uint256[](_vaults.length);

        for (uint256 i = 0; i < _vaults.length; i++) {
            address borrowedRewardPool = IAbstractVault(_vaults[i]).borrowedRewardPool();

            underlyingTokens[i] = IAbstractVault(_vaults[i]).underlyingToken();
            total[i] = IBaseReward(borrowedRewardPool).totalSupply();

            for (uint256 j = 0; j < IAbstractVault(_vaults[i]).creditManagersCount(); j++) {
                address creditManager = IAbstractVault(_vaults[i]).creditManagers(j);
                address shareLocker = IAbstractVault(_vaults[i]).creditManagersShareLocker(creditManager);

                total[i] -= IBaseReward(borrowedRewardPool).balanceOf(shareLocker);
            }
        }

        return (underlyingTokens, total);
    }
}

