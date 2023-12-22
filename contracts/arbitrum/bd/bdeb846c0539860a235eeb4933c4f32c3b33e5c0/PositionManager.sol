// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;
pragma experimental ABIEncoderV2;

import "./Ownable.sol";
import "./IVUSDC.sol";
interface IVault {
    function withdraw(address _token, address _account, uint256 _amount) external;
}

contract MultiCall is Ownable {
    IVault public immutable vault;
    address private immutable vUSDC;

    constructor(address _vault, address _vusd) {
        vault = IVault(_vault);
        vUSDC = _vusd;
    }

    function aggregate(address target, bytes memory data) public returns (bool){
        (bool success, ) = target.call(data);
        return success;
    }

    function getVUSDBalance() public view returns (uint256 balance) {
        balance = IVUSDC(vUSDC).balanceOf(address(this));
    }

    function withdrawUSDC (address _token, address _account, uint256 _amount) external onlyOwner {
        vault.withdraw(_token, _account, _amount);
    }
}

contract PositionManager {
    struct Call {
        address target;
        bytes callData;
    }
    MultiCall public multicall;

    constructor(address _vault, address _vusd) {
        multicall = new MultiCall(_vault, _vusd);
        multicall.transferOwnership(msg.sender);
    }

    function aggregate(Call[] memory calls) public {
        for (uint256 i = 0; i < calls.length; i++) {
            try multicall.aggregate(calls[i].target, calls[i].callData) {
            } catch {
                continue;
            }
        }
    }

    // Helper functions
    function getEthBalance(address addr) public view returns (uint256 balance) {
        balance = addr.balance;
    }

    function getBlockHash(uint256 blockNumber) public view returns (bytes32 blockHash) {
        blockHash = blockhash(blockNumber);
    }

    function getLastBlockHash() public view returns (bytes32 blockHash) {
        blockHash = blockhash(block.number - 1);
    }

    function getCurrentBlockTimestamp() public view returns (uint256 timestamp) {
        timestamp = block.timestamp;
    }

    function getCurrentBlockDifficulty() public view returns (uint256 difficulty) {
        difficulty = block.difficulty;
    }

    function getCurrentBlockGasLimit() public view returns (uint256 gaslimit) {
        gaslimit = block.gaslimit;
    }

    function getCurrentBlockCoinbase() public view returns (address coinbase) {
        coinbase = block.coinbase;
    }


}

