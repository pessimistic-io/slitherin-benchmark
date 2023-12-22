// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.7.6;

import "./IUniswapV3Factory.sol";
import "./Ownable.sol";
import "./VaultEnterprise.sol";
import "./IVaultSwap.sol";

contract VaultEnterpriseFactory is Ownable {
    IUniswapV3Factory public uniswapV3Factory;
    mapping(address => address[]) public getVaults; // pool -> vaults

    address[] public allVaults;

    event VaultCreated(address pool, address vault, uint256);

    constructor(address _uniswapV3Factory) {
        require(_uniswapV3Factory != address(0));
        uniswapV3Factory = IUniswapV3Factory(_uniswapV3Factory);
    }

    /// @notice Create a VaultEnterprise
    /// @param pool Address of the vault's pool
    /// @param name Name of the vault
    /// @param symbol Symbole of the vault
    /// @return vault Address of vault created
    function createVault(
        address pool,
        string memory name,
        string memory symbol,
        int24 tickLower,
        int24 tickUpper,
        uint16 managementFee,
        IVaultSwap vaultSwap
    ) external onlyOwner returns (address vault) {
        require(pool != address(0));
        vault = address(
            new VaultEnterprise{salt: keccak256(abi.encodePacked(pool))}(
                pool,
                owner(),
                name,
                symbol,
                tickLower,
                tickUpper,
                managementFee,
                vaultSwap
            )
        );
        getVaults[pool].push(vault);
        allVaults.push(vault);
        emit VaultCreated(pool, vault, allVaults.length);
    }

    /// @notice Return all vaults created
    function getAllVaults() external view returns (address[] memory) {
        return allVaults;
    }

    /// @notice Return all vaults created for a given pool
    function getVaultsByPool(
        address pool
    ) external view returns (address[] memory) {
        return getVaults[pool];
    }

    /// @notice Get the number of vaults created
    /// @return Number of vaults created
    function allVaultsLength() external view returns (uint256) {
        return allVaults.length;
    }
}

