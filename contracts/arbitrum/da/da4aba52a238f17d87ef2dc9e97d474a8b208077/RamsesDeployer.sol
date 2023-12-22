// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "./AccessControlEnumerableUpgradeable.sol";

contract RamsesDeployer is Initializable, AccessControlEnumerableUpgradeable {
    bytes32 public constant DEPLOYER_ROLE = keccak256("DEPLOYER_ROLE");

    address[] public deployedContracts;

    function initialize(address admin, address deployer) public initializer {
        __AccessControlEnumerable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(DEPLOYER_ROLE, deployer);
    }

    function deploy(bytes memory bytecode, uint256 _salt)
        public
        onlyRole(DEPLOYER_ROLE)
        returns (address contractAddress)
    {
        assembly {
            contractAddress := create2(
                0,
                add(bytecode, 32),
                mload(bytecode),
                _salt
            )
        }
        require(contractAddress != address(0), "create2 failed");

        deployedContracts.push(contractAddress);

        return contractAddress;
    }

    function deployMany(bytes memory bytecode, uint256[] memory salts)
        external
        onlyRole(DEPLOYER_ROLE)
        returns (address[] memory contractAddresses)
    {
        contractAddresses = new address[](salts.length);
        for (uint256 i; i < contractAddresses.length; i++) {
            contractAddresses[i] = deploy(bytecode, salts[i]);
        }
    }

    function deployedContractsLength() external view returns (uint256) {
        return deployedContracts.length;
    }

    function getDeployedContracts() external view returns (address[] memory) {
        return deployedContracts;
    }
}

