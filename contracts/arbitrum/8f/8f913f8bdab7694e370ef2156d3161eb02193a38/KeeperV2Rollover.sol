// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;
import { OpsReady, IOps } from "./OpsReady.sol";
import {IControllerPeggedAssetV2 as IController} from "./IControllerPeggedAssetV2.sol";
import {ICarousel} from "./ICarousel.sol";
import {IVaultFactoryV2} from "./IVaultFactoryV2.sol";
import {Ownable} from "./Ownable.sol";
import {IERC20} from "./IERC20.sol";

contract KeeperV2Rollover is OpsReady, Ownable {
    IVaultFactoryV2 public immutable factory;
    mapping(bytes32 => bytes32) public tasks;

    constructor(address payable _ops, address payable _treasuryTask,address _factory) OpsReady(_ops, _treasuryTask) {
        factory = IVaultFactoryV2(_factory);
    }
    
    function startTask(uint256 _marketIndex, uint256 _epochID) external {
        bytes32 taskId = IOps(ops).createTask(
            address(this), 
            this.executePayload.selector,
            address(this),
            abi.encodeWithSelector(this.checker.selector, _marketIndex, _epochID)
        );
        bytes32 payloadKey  = keccak256(abi.encodePacked(_marketIndex, _epochID));
        tasks[payloadKey] = taskId;
    }
    
    function executePayload(bytes memory _payloadData) external onlyOps {
        (bytes memory callData, address vault) = abi.decode(_payloadData, (bytes, address));
        
        //execute task
        (bool success, ) = vault.call(callData);
        require(success, "executePayload: call failed");

        //cancel task
        // IOps(ops).cancelTask(taskId);
    }
    
    function checker(uint256 _marketIndex, uint256 _epochID)
        external
        view
        returns (bool canExec, bytes memory execPayload)
    {
        address[2] memory vaults = factory.marketIdToVaults(_marketIndex);
        ICarousel premium = ICarousel(vaults[0]);
        ICarousel collat = ICarousel(vaults[1]);
        //check if task can be executed
        if(premium.getDepositQueueTVL() > 0) {
            canExec  = true;
            execPayload = abi.encodeWithSelector(ICarousel.mintDepositInQueue.selector, _epochID, 100);
            execPayload = abi.encode(execPayload, address(premium));
            return (canExec, execPayload);
        }

        if(collat.getDepositQueueTVL() > 0) {
            canExec  = true;
            execPayload = abi.encodeWithSelector(ICarousel.mintDepositInQueue.selector, _epochID, 100);
            execPayload = abi.encode(execPayload, address(collat));
            return (canExec, execPayload);
        }

        if(premium.getRolloverTVL() > 0) {
            canExec  = true;
            execPayload = abi.encodeWithSelector(ICarousel.mintRollovers.selector, _epochID, 100);
            execPayload = abi.encode(execPayload, address(premium));
            return (canExec, execPayload);
        }

        if(collat.getRolloverTVL() > 0) {
            canExec  = true;
            execPayload = abi.encodeWithSelector(ICarousel.mintRollovers.selector, _epochID, 100);
            execPayload = abi.encode(execPayload, address(collat));
            return (canExec, execPayload);
        }
        
    }

    function cancelTask(uint256 _marketIndex, uint256 _epochID) external {
        bytes32 payloadKey  = keccak256(abi.encodePacked(_marketIndex, _epochID));
        bytes32 taskId = tasks[payloadKey];
        IOps(ops).cancelTask(taskId);
    }

    function deposit(uint256 _amount) external payable {
        treasury.depositFunds{value: _amount}(address(this), ETH, _amount);
    }

    function withdraw(uint256 _amount) external onlyOwner{
        treasury.withdrawFunds(payable(msg.sender), ETH, _amount);
    }

    function withdrawFunds(address erc20, uint256 _amount) external onlyOwner{
       IERC20(erc20).transfer(msg.sender, _amount);
    }
}
