// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import {Ownable} from "./Ownable.sol";
import {IERC20} from "./IERC20.sol";
import {IStrategyVault} from "./IStrategyVault.sol";
import {IEarthquakeV2} from "./IEarthquakeV2.sol";
import {IHook} from "./IHook.sol";

contract VaultData is Ownable {
    struct VaultInfo {
        string name;
        string symbol;
        address vaultAddress;
        address depositAsset;
        uint256 deploymentId;
        uint256 maxQueueSize;
        uint256 minDeposit;
        address owner;
        bool fundsDeployed;
        uint256 weightId;
        uint256 weightProportion;
        uint256[] weights;
        address[] marketAddresses;
        uint256[] marketIds;
        uint256 underlyingBalance;
        uint256 emissionBalance;
        uint256 totalSharesIssued;
        address hook;
        uint16 hookCommand;
    }

    event NewVaultInfo(VaultInfo vault);
    event NewVaultInfoBulk(VaultInfo[] vaults);
    event UpdateMarkets(
        address[] markets,
        uint256[] marketIds,
        string[] marketName,
        bool[] isWeth,
        uint256[] strike,
        string[] symbol,
        address[] token,
        address[] depositAsset
    );
    event RemoveVaults(address[] strategyVaults);

    constructor() {}

    //////////////////////////////////////////////
    //                 PUBLIC - ADMIN          //
    //////////////////////////////////////////////
    function updateMarkets(
        address[] calldata markets,
        uint256[] calldata marketIds
    ) external onlyOwner {
        (
            string[] memory marketName,
            bool[] memory isWeth,
            uint256[] memory strike,
            string[] memory symbol,
            address[] memory token,
            address[] memory depositAsset
        ) = _fetchMarketInfo(markets);
        emit UpdateMarkets(
            markets,
            marketIds,
            marketName,
            isWeth,
            strike,
            symbol,
            token,
            depositAsset
        );
    }

    function _fetchMarketInfo(
        address[] calldata markets
    )
        internal
        view
        returns (
            string[] memory marketName,
            bool[] memory isWeth,
            uint256[] memory strike,
            string[] memory symbol,
            address[] memory token,
            address[] memory depositAsset
        )
    {
        marketName = new string[](markets.length);
        isWeth = new bool[](markets.length);
        strike = new uint256[](markets.length);
        symbol = new string[](markets.length);
        token = new address[](markets.length);
        depositAsset = new address[](markets.length);

        for (uint256 i; i < markets.length; ) {
            marketName[i] = IEarthquakeV2(markets[i]).name();
            isWeth[i] = IEarthquakeV2(markets[i]).isWeth();
            strike[i] = IEarthquakeV2(markets[i]).strike();
            symbol[i] = IEarthquakeV2(markets[i]).symbol();
            token[i] = IEarthquakeV2(markets[i]).token();
            depositAsset[i] = IEarthquakeV2(markets[i]).asset();
            unchecked {
                i++;
            }
        }
    }

    /**
        @notice Emits an event for list of vaults
        @dev Subgraph recognising 1 as blacklist and 2 for un-blacklist
     */
    function removeVaults(
        address[] calldata strategyVaults
    ) external onlyOwner {
        emit RemoveVaults(strategyVaults);
    }

    //////////////////////////////////////////////
    //                 PUBLIC - CONFIG          //
    //////////////////////////////////////////////
    function addNewVault(address _strategyVault) external {
        VaultInfo memory vaultInfo = _addNewVault(_strategyVault);
        emit NewVaultInfo(vaultInfo);
    }

    /**
        @notice Loops through an array of new strategy vaults and emits events for each
     */
    function addNewVaults(address[] memory _strategyVaults) external {
        VaultInfo[] memory vaultInfos = new VaultInfo[](_strategyVaults.length);

        for (uint256 i; i < _strategyVaults.length; ) {
            vaultInfos[i] = _addNewVault(_strategyVaults[i]);
            unchecked {
                i++;
            }
        }

        emit NewVaultInfoBulk(vaultInfos);
    }

    //////////////////////////////////////////////
    //                 INTERNAL - CONFIG        //
    //////////////////////////////////////////////
    function _addNewVault(
        address _vault
    ) internal view returns (VaultInfo memory info) {
        IStrategyVault iVault = IStrategyVault(_vault);

        // Querying Strategy Vault for basic info
        info = _fetchBasicInfo(info, iVault);

        // Querying Markets for market info
        address[] memory vaultList = iVault.fetchVaultList();
        info.marketAddresses = vaultList;
        info.marketIds = _fetchMarketIds(vaultList);
    }

    function _fetchBasicInfo(
        VaultInfo memory info,
        IStrategyVault vault
    ) internal view returns (VaultInfo memory) {
        // Basic Info
        info.name = vault.name();
        info.symbol = vault.symbol();
        info.vaultAddress = address(vault);
        info.depositAsset = vault.asset();
        info.deploymentId = vault.deploymentId();
        info.owner = vault.owner();
        info.maxQueueSize = vault.maxQueuePull();
        info.minDeposit = vault.minDeposit();
        info.fundsDeployed = vault.fundsDeployed();
        info.underlyingBalance = vault.totalAssets();
        info.emissionBalance = IERC20(vault.emissionToken()).balanceOf(
            address(vault)
        );
        info.totalSharesIssued = vault.totalSupply();

        // Weight Info
        info.weightId = vault.weightId();
        info.weightProportion = vault.weightProportion();
        info.weights = vault.fetchVaultWeights();

        // Hook info
        (info.hook, info.hookCommand) = vault.hook();
        return info;
    }

    function _fetchMarketIds(
        address[] memory vaultList
    ) internal view returns (uint256[] memory marketIds) {
        marketIds = new uint256[](vaultList.length);

        for (uint256 i; i < vaultList.length; ) {
            marketIds[i] = (_fetchMarketId(vaultList[i]));
            unchecked {
                i++;
            }
        }
    }

    function _fetchMarketId(
        address _strategyVault
    ) internal view returns (uint256) {
        IEarthquakeV2 earthquakeVault = IEarthquakeV2(_strategyVault);
        // We know this is a V2 market
        address _token = earthquakeVault.token();
        uint256 _strikePrice = earthquakeVault.strike();
        address _underlying = earthquakeVault.asset();
        return
            uint256(
                keccak256(abi.encodePacked(_token, _strikePrice, _underlying))
            );
    }
}

