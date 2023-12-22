// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.0;

import "./Ownable.sol";
import "./Create2.sol";
import "./Math.sol";
import "./IDestroy.sol";

contract DeployerBytecode is Ownable {

    using Math for uint256;

    constructor(address owner) {
        transferOwnership(owner);
    }

    function create(bytes memory bytecode) public onlyOwner returns (address deployedContract) {
        assembly { 
            deployedContract := create(0, add(bytecode, 32), mload(bytecode)) 
        }
        require(deployedContract != address(0), 'Failed to deploy contract with CREATE opcode');
        return deployedContract;
    }

    function create2(bytes memory bytecode, bytes32 salt) payable public onlyOwner returns (address deployedContract) {
        deployedContract = Create2.deploy(0, salt, bytecode);
        return deployedContract;
    }

    function deploy(bytes memory bytecode, bytes32 salt) payable external onlyOwner returns (address deployedContract) {
        return create2(bytecode, salt);
    }

    function giveBackEth() external onlyOwner {
        payable(msg.sender).transfer(address(this).balance);
    }

    function transferOwnershipBack(address deployedContract) external onlyOwner {
        if (deployedContract != address(0)) {
            Ownable newDeployedContract = Ownable(deployedContract);
            newDeployedContract.transferOwnership(owner());
        }
    }

    function destroyContract(address contractAddress) external onlyOwner {
        IDestroy contractToDestroy = IDestroy(contractAddress);
        contractToDestroy.destroy();
    }

    function destroy() external onlyOwner {
        selfdestruct(payable(msg.sender));
    }
}

