// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import "./Ownable.sol";
import "./ERC20.sol";
import "./INonfungiblePositionManager.sol";
import "./BuyerLocker.sol";
import "./BaseLocker.sol";

contract LiquidityLocker is BuyerLocker {
    address public uniswapNFT;

    function _init() internal override {
        uniswapNFT = 0xC36442b4a4522E871399CD717aBDD847Ab11FE88;
        BuyerLocker._init();
    }

    function startLock(
        uint256 tokenID,
        uint256 secondsToLock
    ) external payable {
        require(
            INonfungiblePositionManager(uniswapNFT).getApproved(tokenID) ==
                address(this),
            "Locker needs approval to transfer Uniswap NFT."
        );
        _payment();
        address withdrawalAddress = msg.sender;
        _newLock(withdrawalAddress, tokenID, block.timestamp + secondsToLock);
        INonfungiblePositionManager(uniswapNFT).transferFrom(
            withdrawalAddress,
            address(this),
            tokenID
        );
        emit TransferNFT(withdrawalAddress, address(this), tokenID);
    }

    function updateLock(
        uint256 idx,
        uint256 secondsToLock
    ) external payable onlyWithdrawalAddress(idx) {
        _payment();
        _updateLock(idx, msg.sender, block.timestamp + secondsToLock);
    }

    function transfertNFT(
        uint256 idx,
        address newWithdrawalAddress
    ) external payable onlyWithdrawalAddress(idx) {
        _payment();
        Lock storage lock = locks[idx];
        _updateLock(idx, newWithdrawalAddress, lock.unlockTime);
        emit TransferNFT(msg.sender, newWithdrawalAddress, lock.tokenID);
    }

    function sendBackNFT(uint256 idx) external onlyWithdrawalAddress(idx) {
        address withdrawalAddress = msg.sender;
        Lock memory lock = locks[idx];
        _deleteLock(idx, withdrawalAddress);
        INonfungiblePositionManager(uniswapNFT).transferFrom(
            address(this),
            withdrawalAddress,
            lock.tokenID
        );
        emit TransferNFT(address(this), withdrawalAddress, lock.tokenID);
    }

    function collectFees(
        uint256 idx
    )
        public
        onlyWithdrawalAddress(idx)
        returns (uint256 amount0, uint256 amount1)
    {
        Lock memory lock = locks[idx];
        (
            ,
            ,
            address token0,
            address token1,
            ,
            ,
            ,
            ,
            ,
            ,
            ,

        ) = INonfungiblePositionManager(uniswapNFT).positions(lock.tokenID);
        INonfungiblePositionManager.CollectParams
            memory params = INonfungiblePositionManager.CollectParams({
                tokenId: lock.tokenID,
                recipient: address(this),
                amount0Max: type(uint128).max,
                amount1Max: type(uint128).max
            });
        (amount0, amount1) = INonfungiblePositionManager(uniswapNFT).collect(
            params
        );
        ERC20(token0).transfer(lock.withdrawalAddress, amount0);
        ERC20(token1).transfer(lock.withdrawalAddress, amount1);
    }

    function collectAllFees() external {
        uint256[] memory ids = locksOfWithdrawalAddress[msg.sender];
        for (uint i = 0; i < ids.length; i++) {
            collectFees(ids[i]);
        }
    }

    function setUniswapNFT(address addr) external onlyOwner {
        uniswapNFT = addr;
    }
}

