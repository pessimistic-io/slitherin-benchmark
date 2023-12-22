/**
 * SPDX-License-Identifier: Proprietary
 * 
 * Strateg Protocol contract
 * PROPRIETARY SOFTWARE AND LICENSE. 
 * This contract is the valuable and proprietary property of Strateg Development Association. 
 * Strateg Development Association shall retain exclusive title to this property, and all modifications, 
 * implementations, derivative works, upgrades, productizations and subsequent releases. 
 * To the extent that developers in any way contributes to the further development of Strateg protocol contracts, 
 * developers hereby irrevocably assign and/or agrees to assign all rights in any such contributions or further developments to Strateg Development Association. 
 * Without limitation, Strateg Development Association acknowledges and agrees that all patent rights, 
 * copyrights in and to the Strateg protocol contracts shall remain the exclusive property of Strateg Development Association at all times.
 * 
 * DEVELOPERS SHALL NOT, IN WHOLE OR IN PART, AT ANY TIME: 
 * (i) SELL, ASSIGN, LEASE, DISTRIBUTE, OR OTHER WISE TRANSFER THE STRATEG PROTOCOL CONTRACTS TO ANY THIRD PARTY; 
 * (ii) COPY OR REPRODUCE THE STRATEG PROTOCOL CONTRACTS IN ANY MANNER;
 */
pragma solidity ^0.8.15;

import "./Ownable.sol";
import "./IERC20.sol";
import {StrategVault} from "./StrategVault.sol";
import {IStrategVaultFactory} from "./IStrategVaultFactory.sol";

contract StrategVaultFactory is Ownable, IStrategVaultFactory {

    address public registry;
    address public feeCollector;

    uint256 public vaultsLength;
    mapping(uint256 => address) public vaults;

    mapping(address => bool) private gatewayAllowed;

    mapping(address => uint256) private ownedVaultsIndex;
    mapping(address => mapping(uint256 => uint256)) private ownedVaults;

    /**
     * @dev Set the underlying asset contract. This must be an ERC20-compatible contract (ERC20 or ERC777).
     */
    constructor(address _registry, address _feeCollector) {
        registry = _registry;
        feeCollector = _feeCollector;
    }

    function deployNewVault(
        string memory _name,
        string memory _symbol,
        address _asset,
        uint256 _performanceFees
    ) external {
        StrategVault vault = new StrategVault(
            feeCollector,
            registry,
            _name,
            _symbol,
            _asset,
            _performanceFees
        );

        vault.transferOwnership(msg.sender);

        vaults[vaultsLength] = address(vault);

        ownedVaults[msg.sender][ownedVaultsIndex[msg.sender]] = vaultsLength;

        vaultsLength += 1;
        ownedVaultsIndex[msg.sender] += 1;

        emit NewVault(address(vault), _name, _symbol, _asset, msg.sender);
    }

    function getOwnedVaultBy(address owner)
        external
        view
        returns (uint256[] memory)
    {
        uint256 ownedVaultIndexes = ownedVaultsIndex[owner];
        uint256[] memory vaultIndexes = new uint256[](ownedVaultIndexes);
        for (uint i = 0; i < ownedVaultIndexes; i++) {
            vaultIndexes[i] = ownedVaults[msg.sender][i];
        }

        return vaultIndexes;
    }

    function getBatchVaultAddresses(uint256[] memory indexes)
        external
        view
        returns (address[] memory)
    {
        address[] memory vaultAddresses = new address[](indexes.length);
        for (uint i = 0; i < indexes.length; i++) {
            vaultAddresses[i] = vaults[indexes[i]];
        }

        return vaultAddresses;
    }
}
