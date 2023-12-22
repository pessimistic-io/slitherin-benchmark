// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {IErrors} from "./IErrors.sol";
import {IEarthquake} from "./IEarthquake.sol";
import {IEarthquakeFactory} from "./IEarthquakeFactory.sol";

library VaultGetter {
    /**
        @notice Checks if the list of vaults being provided are valid Y2K vaults
        @dev Checks if address !=0, checks if asset !=0, and checks if emissionToken is valid
        @param vaults the list of vaults to check
     */
    function checkVaultsValid(address[] calldata vaults) public view {
        for (uint256 i = 0; i < vaults.length; ) {
            checkVaultValid(IEarthquake(vaults[i]));

            unchecked {
                i++;
            }
        }
    }

    /**
        @notice Gets the list of epochIds for the vault that are active along with vaultType
        @dev Vaults are only valid where the most recent epoch can be deposited to
        @param vaults the list of vaults to check
        @return epochIds validVaults vaultType - the list of epochIds for the vaults, the list of valid vaults, and the list of vault types
     */
    function fetchEpochIds(
        address[] memory vaults
    )
        public
        view
        returns (
            uint256[] memory epochIds,
            address[] memory validVaults,
            uint256[] memory vaultType
        )
    {
        uint256 validCount;
        epochIds = new uint256[](vaults.length);
        validVaults = new address[](vaults.length);
        vaultType = new uint256[](vaults.length);

        for (uint256 i = 0; i < vaults.length; ) {
            IEarthquake vault = IEarthquake(vaults[i]);

            bool valid;
            (valid, epochIds[i], vaultType[i]) = epochValid(vault);
            unchecked {
                i++;
            }

            if (!valid) {
                continue;
            }

            validVaults[validCount] = address(vault);
            unchecked {
                validCount++;
            }
        }
    }

    /**
        @notice Checks if a vault has a valid epoch
        @dev Vault is valid where length >0, most recent epochId has not ended, and most recent epochId has not begun. When
        vaults is V1 calls differ hence the use of a try/catch block returning vaultType depending on block
        @param vault the vault to check
        @return valid epochId vaultType - the validity of the vault, the epochId, and the vaultType
     */
    function epochValid(
        IEarthquake vault
    ) public view returns (bool, uint256, uint256) {
        try vault.epochsLength() returns (uint256 epochLength) {
            if (epochLength == 0) return (false, 0, 0);

            uint256 epochId = vault.epochs(epochLength - 1);
            if (vault.idEpochEnded(epochId)) return (false, 0, 0);

            if (block.timestamp > vault.idEpochBegin(epochId))
                return (false, 0, 0);
            return (true, epochId, 1);
        } catch {
            try vault.getEpochsLength() returns (uint256 epochLength) {
                if (epochLength == 0) return (false, 0, 0);

                uint256 epochId = vault.epochs(epochLength - 1);
                (uint40 epochBegin, uint40 epochEnd, ) = vault.getEpochConfig(
                    epochId
                );

                if (block.timestamp > epochEnd) return (false, 0, 0);
                if (block.timestamp > epochBegin) return (false, 0, 0);
                return (true, epochId, 2);
            } catch {
                return (false, 0, 0);
            }
        }
    }

    /**
        @notice Gets the roi for an epochId for an Earthquake vault
        @dev Roi is calculated as the counterPartyVault supply / vault supply * 10_000 (for an epochId)
        @param vault the vault to check
        @param epochId the epochId to check
        @param marketId the marketId to check
     */
    function getRoi(
        address vault,
        uint256 epochId,
        uint256 marketId
    ) public view returns (uint256) {
        uint256 vaultSupply = IEarthquake(vault).totalSupply(epochId);

        address counterVault;
        IEarthquake iVault = IEarthquake(vault);
        try iVault.counterPartyVault() returns (address vaultAddr) {
            counterVault = vaultAddr;
        } catch {
            address[] memory vaults = IEarthquakeFactory(iVault.factory())
                .getVaults(marketId);
            counterVault = vaults[0] == vault ? vaults[1] : vaults[0];
        }

        uint256 counterSupply = IEarthquake(counterVault).totalSupply(epochId);
        return (counterSupply * 10_000) / vaultSupply;
    }

    /**
        @notice Checks if the vault has key inputs
        @dev Vault could be dupped with these inputs but as usage is for our inputs only
        it's more of a sanity check the vault input being used by an admin is valid
        @param _vault the vault to check
     */
    function checkVaultValid(IEarthquake _vault) public view {
        if (address(_vault) == address(0)) revert IErrors.InvalidVaultAddress();

        if (address(_vault.asset()) == address(0))
            revert IErrors.InvalidVaultAsset();

        if (_vault.controller() == address(0))
            revert IErrors.InvalidVaultController();

        if (_vault.treasury() == address(0)) revert IErrors.InvalidTreasury();

        try _vault.emissionsToken() returns (address emissionsToken) {
            if (emissionsToken == address(0))
                revert IErrors.InvalidVaultEmissions();
            if (_vault.counterPartyVault() == address(0))
                revert IErrors.InvalidVaultCounterParty();
        } catch {
            // NOTE: V1 vaults do not have emissionsToken storage variable
        }
    }

    /**
        @notice Checks if the market is valid
        @dev if the factory returns an empty array then the market is not valid - where market is a vault address
        @param _vault the vault to check
        @param _marketId the marketId to check
     */
    function checkMarketValid(
        IEarthquake _vault,
        uint256 _marketId
    ) public view {
        // NOTE: Factory will vary but implementation for calls is the same
        IEarthquakeFactory factory = IEarthquakeFactory(
            address(_vault.factory())
        );
        address[] memory vaults = factory.getVaults(_marketId);
        if (vaults[0] == address(0)) revert IErrors.MarketNotExist();
    }
}

