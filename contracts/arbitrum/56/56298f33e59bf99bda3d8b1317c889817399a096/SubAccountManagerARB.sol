// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.10;

import { ProxyAdmin } from "./ProxyAdmin.sol";
import { TransparentUpgradeableProxy } from "./TransparentUpgradeableProxy.sol";
import { Ownable } from "./access_Ownable.sol";
import { ICounterPartyRegistry } from "./ICounterPartyRegistry.sol";

/**
 * @title SubAccount manager
 */
contract SubAccountManagerARB is Ownable {

    //fee collector address
    address public feeCollector;

    //operator
    address public operator;

    //counter party registry
    address public counterPartyRegistry;

    //swap contract manager
    address public swapContractManager;

    //map owner address to array of subaccounts
    mapping(address => address[]) public ownerSubAccounts;

    /**
     * @notice Deploy sub account.
     * @param adminAddress Address of the subaccount proxy admin
     * @param proxyAddress Address of the subaccount proxy address/
     */
    event DeploySubAccount(address adminAddress, address proxyAddress);

    /**
     * @notice Add a subaccount.
     * @param owner Owner of the subaccount.
     * @param subAccount Address of the subaccount.
     */
    event AddSubAccount(address owner, address subAccount);

    /**
     * @notice Remove a subaccount.
     * @param owner Owner of the subaccount.
     * @param subAccount Address of the subaccount.
     */
    event RemoveSubAccount(address owner, address subAccount);

    /**
     * @notice Set the operator.
     * @param operator Address of the operator.
     */
    event SetOperator(address operator);

    /**
     * @notice Set swap contract manager.
     * @param swapContractManager Address of the swap contract manager.
     */
    event SetSwapContractManager(address swapContractManager);

    /**
     * @notice Set swap contract manager.
     * @param counterPartyRegistry Address of the counter party registry.
     */
    event SetCounterPartyRegistry(address counterPartyRegistry);

    /**
     * @notice initialize contract.
     * @param feeCollectorAddr Address of the fee collector.
     * @param operatorAddr Address of the fractal operator.
     */
    constructor(
        address feeCollectorAddr,
        address operatorAddr
    ){
        require(feeCollectorAddr != address(0), '0 address');
        require(operatorAddr != address(0), '0 address');
        
        feeCollector = feeCollectorAddr;
        operator = operatorAddr;
    }

    /**
     * @notice Sets the operator. 
     * @param operatorAddress Specifies the address of the poolContract. 
     */
    function setOperator(address operatorAddress) external onlyOwner {
        //set operator
        operator = operatorAddress;
        //emit
        emit SetOperator(operator);
    }

    /**
     * @notice Set swap contract manager.
     * @param swapContractManagerAddr Address of the swap contract manager.
     */
    function setSwapContractManager(address swapContractManagerAddr) external onlyOwner {
        //set swap contract mananger
        swapContractManager = swapContractManagerAddr;
        //emit
        emit SetSwapContractManager(swapContractManager);
    }

    /**
     * @notice Set swap contract manager.
     * @param counterPartyRegistryAddr The counter party registry address.
     */
    function setCounterPartyRegistry(address counterPartyRegistryAddr) external onlyOwner {
        //set swap contract mananger
        counterPartyRegistry = counterPartyRegistryAddr;
        //emit
        emit SetCounterPartyRegistry(counterPartyRegistry);
    }
    
    /**
     * @notice Deploy and initialize a subaccount proxy contract. 
     * @param adminSalt encrypted password for proxy admin.
     * @param proxySalt encrypted password for proxy contract.
     * @param implementationAddr implementation address used for the proxy contract.
     * @param proxyOwnerAddr owner of the admin and proxy contracts.
     */
    function deployAndInitializeSubAccount(
        bytes32 adminSalt,
        bytes32 proxySalt,
        address implementationAddr,
        address proxyOwnerAddr
    ) external onlyOwner
    {
        //zero bytes
        bytes memory ZERO_BYTES = new bytes(0);
        // Basic check of input parameters
        require(adminSalt != bytes32(0), "Admin salt required");
        require(proxySalt != bytes32(0), "Proxy salt required");
        require(implementationAddr != address(0) && implementationAddr != address(this), "Invalid logic address");

        // Get the predictable address of both the proxy and the proxy admin
        (address adminContractAddr, address proxyContractAddr) = getDeploymentAddress(adminSalt, proxySalt, implementationAddr, ZERO_BYTES);

        // Make sure the contract addresses above were not taken
        require(adminContractAddr.code.length == 0, "Admin address already taken");
        require(proxyContractAddr.code.length == 0, "Proxy address already taken");

        // Deploy the proxy admin
        ProxyAdmin adminInstance = (new ProxyAdmin){salt: adminSalt}();
        require(address(adminInstance) == adminContractAddr, "Admin deploy failed");

        // Deploy the transparent proxy
        TransparentUpgradeableProxy proxy = (new TransparentUpgradeableProxy){salt: proxySalt}(implementationAddr, address(adminInstance), ZERO_BYTES);
        require(address(proxy) == proxyContractAddr, "Proxy deploy failed");

        //initialize the transparent proxy
        bytes memory subAccountData = abi.encodeWithSignature("initialize(address,address,address,address,address)", proxyOwnerAddr, operator, feeCollector, swapContractManager, counterPartyRegistry);
        adminInstance.upgradeAndCall(TransparentUpgradeableProxy(payable(proxyContractAddr)), implementationAddr, subAccountData);

        //transfer ownership of admin to proxy owner
        adminInstance.transferOwnership(proxyOwnerAddr);

        //push new subaccount into owner array
        ownerSubAccounts[proxyOwnerAddr].push(address(proxy));

        //add subaccount to counterparty registry
        ICounterPartyRegistry(counterPartyRegistry).addCounterParty(address(proxy));

        emit DeploySubAccount(address(adminInstance), address(proxy));
    }

    /**
     * @notice Owner method for adding subaccount.
     * @dev Primarily used for migrating subaccounts if this contract is switched. 
     * @param owner The owner of the subaccount
     * @param subAccount The subaccount address
     */
    function addSubAccount(address owner, address subAccount) external onlyOwner {
        //push into array
        ownerSubAccounts[owner].push(subAccount);
        //emit
        emit AddSubAccount(owner, subAccount);
    }

    /**
     * @notice Owner method for removing subaccount for a specific owner. 
     * @param owner The owner of the subaccount
     * @param subAccount The subaccount address
     */
    function removeSubAccount(address owner, address subAccount) external onlyOwner {
        //store new array
        address[] storage subAccountToRemove = ownerSubAccounts[owner];
        //cache length
        uint256 length = subAccountToRemove.length;
        for (uint256 i = 0; i < length;) {
            if (subAccount == subAccountToRemove[i]) {
                subAccountToRemove[i] = subAccountToRemove[length - 1];
                subAccountToRemove.pop();
                break;
            }

            unchecked { ++i; }
        }
        ownerSubAccounts[owner] = subAccountToRemove;

        emit RemoveSubAccount(owner, subAccount);
    }


    /**
     * @notice Get the proxy admin and proxy contract deployment addresses
     * @param adminSalt encrypted password for proxy admin.
     * @param proxySalt encrypted password for proxy contract.
     * @param implementationAddr implementation address used for the proxy contract.
     * @param initData initialized bytes data. 
     */
    function getDeploymentAddress(
        bytes32 adminSalt, 
        bytes32 proxySalt, 
        address implementationAddr, 
        bytes memory initData) public view returns (address adminContractAddr, address proxyContractAddr) {
        adminContractAddr = address(uint160(uint256(
                                keccak256(abi.encodePacked(bytes1(0xff), address(this), adminSalt, keccak256(type(ProxyAdmin).creationCode)))
                            )));

        proxyContractAddr = address(uint160(uint256(
                                keccak256(abi.encodePacked(bytes1(0xff), address(this), proxySalt, keccak256(
                                    abi.encodePacked(type(TransparentUpgradeableProxy).creationCode, abi.encode(implementationAddr, adminContractAddr, initData))
                                )))
                            )));
    }

    /**
     * @notice Return array of subaccounts for a corresponding owner address. 
     * @param owner The owner of the subaccount
     */
    function getSubAccounts(address owner) external view returns (address[] memory)
    {
        return ownerSubAccounts[owner];
    }

}
