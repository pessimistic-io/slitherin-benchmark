// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.7.6;

import "./IUniswapV3Factory.sol";

import "./Ownable.sol";

import "./VaultEnterprise.sol";

contract VaultEnterpriseFactory is Ownable {
    IUniswapV3Factory public uniswapV3Factory;
    mapping(address => address) public getVault; // token0, token1, fee -> vault address
    address[] public allVaults;

    event VaultCreated(address pool, address vault, uint256);

    constructor(address _uniswapV3Factory) {
        require(
            _uniswapV3Factory != address(0),
            "uniswapV3Factory should be non-zero"
        );
        uniswapV3Factory = IUniswapV3Factory(_uniswapV3Factory);
    }

    /// @notice Get the number of vaults created
    /// @return Number of vaults created
    function allVaultsLength() external view returns (uint256) {
        return allVaults.length;
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
        uint8 managementFee
    ) external onlyOwner returns (address vault) {
        require(pool != address(0), "Invalid pool");
        require(getVault[pool] == address(0), "Vault exists");
        vault = address(
            new VaultEnterprise{salt: keccak256(abi.encodePacked(pool))}(
                pool,
                owner(),
                name,
                symbol,
                tickLower,
                tickUpper,
                managementFee
            )
        );

        getVault[pool] = vault;
        allVaults.push(vault);
        emit VaultCreated(pool, vault, allVaults.length);
    }

    /// @notice Return all vaults created
    function getAllVaults() external view returns (address[] memory) {
        return allVaults;
    }
}

