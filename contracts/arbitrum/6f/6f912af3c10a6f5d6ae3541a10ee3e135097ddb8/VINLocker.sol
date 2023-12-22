// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "./Ownable.sol";
import "./IERC20.sol";

contract VINLocker is Ownable {
    struct LockDetail {
        uint256 amount;
        uint256 releaseTime;
    }
    IStrictERC20 public vin;
    mapping(address => LockDetail[]) public locking;
    mapping(address => uint256) public releaseIndex;

    event Lock(address user, uint256 amount, uint256 releaseTime);

    constructor(address _vin) {
        vin = IStrictERC20(_vin);
    }

    function lock(LockDetail[] memory locks, address claimer) external onlyOwner {
        uint256 total;
        for (uint256 i = 0; i < locks.length; i++) {
            require(locks[i].releaseTime > block.timestamp);
            total += locks[i].amount;
            locking[claimer].push(locks[i]);
        }
        vin.transferFrom(msg.sender, address(this), total);
    }

    function claim() external {
        uint256 total;
        address to = msg.sender;
        LockDetail[] memory locks = locking[to];
        uint256 i = releaseIndex[to];
        for (; i < locks.length && locks[i].releaseTime < block.timestamp; i++) {
            total += locks[i].amount;
        }
        releaseIndex[to] = i;
        vin.transfer(msg.sender, total);
    }

    function transferLOck(address to) external {
        address from = msg.sender;
        releaseIndex[to] = releaseIndex[from];
        locking[to] = locking[from];
        delete releaseIndex[from];
        delete locking[from];
    }
}

