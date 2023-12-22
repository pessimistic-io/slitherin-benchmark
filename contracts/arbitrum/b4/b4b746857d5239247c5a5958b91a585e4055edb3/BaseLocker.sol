// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import "./OwnableUpgradeable.sol";

contract BaseLocker is OwnableUpgradeable {
    struct Lock {
        address withdrawalAddress;
        uint256 tokenID;
        uint256 unlockTime;
    }
    Lock[] public locks;
    mapping(address => uint256[]) public locksOfWithdrawalAddress;
    mapping(address => bool) public withdrawalAddresses;

    modifier onlyWithdrawalAddress(uint256 idx) {
        require(_isWithdrawalAddress(msg.sender), "The sender dont have NFT.");
        require(
            _contain(msg.sender, idx),
            "The sender is not authorized to interact of this NFT."
        );
        _;
    }

    event TransferNFT(
        address indexed from,
        address indexed to,
        uint256 tokenID
    );

    uint256[49] __gap;

    function initialize() public initializer {
        __Ownable_init();
        _init();
    }

    function _init() internal virtual {}

    function getLockCount() public view returns (uint256) {
        return locks.length;
    }

    function hasLockEnded(uint256 idx) public view returns (bool) {
        Lock memory lock = locks[idx];
        if (block.timestamp > lock.unlockTime) return true;
        return false;
    }

    function _isWithdrawalAddress(address add) internal view returns (bool) {
        return withdrawalAddresses[add];
    }

    function _newLock(
        address withdrawalAddress,
        uint256 tokenID,
        uint256 unlockTime
    ) internal returns (uint256) {
        Lock memory lock = Lock(withdrawalAddress, tokenID, unlockTime);
        locks.push(lock);
        uint256 i = locks.length - 1;
        locksOfWithdrawalAddress[withdrawalAddress].push(i);
        withdrawalAddresses[withdrawalAddress] = true;
        return i;
    }

    function _updateLock(
        uint256 idx,
        address withdrawalAddress,
        uint256 unlockTime
    ) internal {
        Lock storage lock = locks[idx];
        if (unlockTime > lock.unlockTime) {
            lock.unlockTime = unlockTime;
        }
        if (lock.withdrawalAddress != withdrawalAddress) {
            uint256[] storage lockOf = locksOfWithdrawalAddress[lock.withdrawalAddress];
            uint256 idxOf = _getIdxOf(idx, lock.withdrawalAddress);
            lockOf[idxOf] = lockOf[lockOf.length - 1];
            if (lockOf.length <= 1) {
                withdrawalAddresses[lock.withdrawalAddress] = false;
            }
            lockOf.pop();
            locksOfWithdrawalAddress[withdrawalAddress].push(idx);
            withdrawalAddresses[withdrawalAddress] = true;
        }
        lock.withdrawalAddress = withdrawalAddress;
    }

    function _deleteLock(
        uint256 idx,
        address withdrawalAddress
    ) internal returns (bool) {
        require(hasLockEnded(idx), "The lock is not ended.");
        uint256[] storage lockOf = locksOfWithdrawalAddress[withdrawalAddress];
        if (lockOf.length <= 1) {
            withdrawalAddresses[withdrawalAddress] = false;
        }
        uint256 idxOf = _getIdxOf(idx, withdrawalAddress);
        lockOf[idxOf] = lockOf[lockOf.length - 1];
        lockOf.pop();
        locks[idx] = locks[locks.length - 1];
        locks.pop();
        return true;
    }

    function _contain(
        address withdrawalAddress,
        uint256 idx
    ) internal view returns (bool) {
        uint256[] memory locksOf = locksOfWithdrawalAddress[withdrawalAddress];
        for (uint256 i = 0; i < locksOf.length; i++) {
            if (locks[locksOf[i]].tokenID == locks[idx].tokenID) {
                return true;
            }
        }
        return false;
    }

    function _getIdxOf(uint256 idx, address withdrawalAddress) private view returns(uint256) {
        uint256[] memory locksOf = locksOfWithdrawalAddress[withdrawalAddress];
        for(uint256 i = 0; i < locksOf.length; i++) {
            if(locksOf[i] == idx){
                return i;
            }
        }
        revert("Not Found"); 
    }

    function getLocksOf(address addr) external view returns (uint256[] memory) {
        return locksOfWithdrawalAddress[addr];
    }

    function setWithdrawalAddresses(address addr) external onlyOwner {
        withdrawalAddresses[addr] = true;
    }

    receive() external payable {}
}

