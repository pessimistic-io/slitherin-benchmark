// SPDX-License-Identifier: MIT
//pragma solidity 0.8.13;

/*
    This contract handles the fee distribution from UniV3 to gauges.
*/

import "./IPermissionsRegistry.sol";
import "./IUniV3Factory.sol";
import "./IUniswapV3Pool.sol";
import "./IVoter.sol";
import "./IERC20.sol";
import "./SafeERC20.sol";

interface IGauge{
    function feeVault() external view returns (address);
}

contract ProtocolFeeHandler {

    IPermissionsRegistry public permissionRegistry;
    IUniV3Factory public uniFactory;
    IVoter public voter;

    constructor(address _permissionRegistry, address _uniFactory, address _voter) public {
        permissionRegistry = IPermissionsRegistry(_permissionRegistry);
        uniFactory = IUniV3Factory(_uniFactory);
        voter = IVoter(_voter);
    }    

    modifier onlyGaugeOrAdmin {
        require(voter.isGauge(msg.sender) || permissionRegistry.hasRole("CL_FEES_VAULT_ADMIN",msg.sender), "ERR: NOT_CL_FEES_ADMIN");
        _;
    }

    modifier onlyAdmin {
        require(permissionRegistry.hasRole("CL_FEES_VAULT_ADMIN",msg.sender), 'ERR: GAUGE_ADMIN');
        _;
    }

    /// @notice Set a new PermissionRegistry
    function setPermissionsRegistry(address _permissionRegistry) external onlyAdmin {
        permissionRegistry = IPermissionsRegistry(_permissionRegistry);
    }

    function changeUniFactory(address _newUniFactory) external onlyAdmin {
        uniFactory = IUniV3Factory(_newUniFactory);
    }

    function passPermissionsBack(address _receiver) external onlyAdmin {
        uniFactory.setOwner(_receiver);
    }

    function changeProtocolFees(address _pool, uint8 _one, uint8 _two) external onlyAdmin {
        IUniswapV3Pool pool = IUniswapV3Pool(_pool);
        pool.setFeeProtocol(_one, _two);
    }

    function collectFee(address _pool) external onlyGaugeOrAdmin {
        IUniswapV3Pool pool = IUniswapV3Pool(_pool);
        address _feeVault = IGauge(voter.gauges(_pool)).feeVault();
        pool.collectProtocol(_feeVault, type(uint128).max, type(uint128).max);
    }
}
