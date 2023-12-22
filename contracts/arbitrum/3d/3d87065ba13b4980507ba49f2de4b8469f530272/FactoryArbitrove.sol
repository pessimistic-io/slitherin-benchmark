pragma solidity 0.8.17;

import "./Ownable.sol";
import "./IERC20.sol";
import "./Vault.sol";
import "./AddressRegistry.sol";
import "./Rebalancer.sol";
import "./TProxy.sol";

contract FactoryArbitrove is Ownable {
    address public addressRegistryAddress;
    address public vaultAddress;
    address public feeOracleAddress;
    address public rebalancerAddress;

    constructor() {
        AddressRegistry ar = new AddressRegistry();
        Vault v = new Vault();
        FeeOracle fO = new FeeOracle();
        addressRegistryAddress = address(ar);
        vaultAddress = address(v);
        feeOracleAddress = address(fO);
    }
    function upgradeImplementation(
        TProxy proxy,
        address newImplementation
    ) external onlyOwner {
        proxy.upgradeTo(newImplementation);
    }
    
}

