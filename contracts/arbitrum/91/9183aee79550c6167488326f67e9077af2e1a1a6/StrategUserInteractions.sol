// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "./IERC20.sol";
import "./SafeERC20.sol";
import { IStrategVault, StrategVaultSettings } from "./IStrategVault.sol";
import { IStrategVaultFactory } from "./IStrategVaultFactory.sol";
import { LibPermit } from "./LibPermit.sol";
import { ERC2771Context } from "./ERC2771Context.sol";

/**
 * @title Strateg interactions helper
 * @notice Additional contract to implement permit1, permit2 anf Gelato relay
 */
contract StrategUserInteractions is ERC2771Context {
    using SafeERC20 for IERC20;

    IStrategVaultFactory factory;
    address permit2;
    address relayer;

    constructor(
        address _relayer,
        address _permit2,
        address _factory
    ) ERC2771Context(relayer) {
        factory = IStrategVaultFactory(_factory);
        permit2 = _permit2;
        relayer = _relayer;
    }

    /**
     * Vault owner actions
     */
    function deployNewVault(
        string memory _name,
        string memory _symbol,
        address _asset,
        uint256 _strategy,
        uint256 _bufferSize,
        uint256 _creatorFees,
        uint256 _harvestFees,
        string memory _ipfsHash
    ) public {
        factory.deployNewVault(
            _name,
            _symbol,
            _msgSender(),
            _asset,
            _strategy,
            _bufferSize,
            _creatorFees,
            _harvestFees,
            _ipfsHash
        );
    }

    function setVaultStrategy(
        address vault,
        address[] memory _positionManagers,
        address[] memory _stratBlocks,
        bytes[] memory _stratBlocksParameters,
        address[] memory _harvestBlocks,
        bytes[] memory _harvestBlocksParameters
    ) public {
        factory.setVaultStrat(
            _msgSender(),
            vault,
            _positionManagers,
            _stratBlocks,
            _stratBlocksParameters,
            _harvestBlocks,
            _harvestBlocksParameters
        );
    }

    function editVaultParams(
        address _vault,
        StrategVaultSettings[] memory settings,
        bytes[] memory data
    ) public {
        factory.editVaultParams(
            _msgSender(),
            _vault,
            settings,
            data
        );
    }

    /**
     * Vault invest actions
     */
    function vaultDeposit(
        address _vault,
        uint256 _assets,
        bytes memory _permitParams
    ) public {

        address sender = _msgSender();
        IStrategVault vault = IStrategVault(_vault);
        IERC20 asset = IERC20(vault.asset());
        
        if(_permitParams.length != 0) {
            LibPermit.executePermit(address(asset), sender, _assets, _permitParams);
        }

        asset.safeTransferFrom(sender, address(this), _assets);
        asset.safeIncreaseAllowance(_vault, _assets);

        vault.deposit(_assets, sender);
    }

    function vaultDepositWithPermit2(
        address _vault,
        uint256 _assets,
        bytes memory _permitParams
    ) public {
        address sender = _msgSender();
        IStrategVault vault = IStrategVault(_vault);
        IERC20 asset = IERC20(vault.asset());
        LibPermit.executeTransferFromPermit2(
            permit2,
            address(asset), 
            sender, 
            address(this), 
            _assets, 
            _permitParams
        );

        asset.safeIncreaseAllowance(_vault, _assets);

        vault.deposit(_assets, sender);
    }

    function vaulWithdraw(
        address _vault,
        uint256 _shares,
        bytes memory _permitParams
    ) public {
        address sender = _msgSender();
        IStrategVault vault = IStrategVault(_vault);
        LibPermit.executePermit(address(vault), sender, _shares, _permitParams);

        vault.transferFrom(sender, address(this), _shares);
        vault.redeem(_shares, sender, address(this));
    }
}

