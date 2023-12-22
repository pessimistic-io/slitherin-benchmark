// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.17;

import {Owned} from "./Owned.sol";
import {CREATE3} from "./CREATE3.sol";
import {SafeTransferLib} from "./SafeTransferLib.sol";
import {RewardRouterV2} from "./IRewardRouterV2.sol";
import {IEscrowController} from "./IEscrowController.sol";
import {Escrow} from "./Escrow.sol";
import {ERC721TokenReceiver} from "./ERC721.sol";

contract EscrowFactory is Owned(tx.origin), ERC721TokenReceiver {
    using SafeTransferLib for address;

    address public rewardRouter;
    address public escrowController;
    uint16 fee = 4900;

    constructor() {
    }

    fallback() external payable { }

    receive() external payable { }

    function setFeeBasisPoints(uint16 newFee) external onlyOwner
    {
        require(newFee <= 10000, "FEE_TOO_LARGE");
        fee = newFee;
    }

    function setRewardRouter(address router) external onlyOwner
    {
        rewardRouter = router;
    }

    function setEscrowController(address controller) external onlyOwner
    {
        escrowController = controller;
    }

    function getSalt(address account) internal view returns (bytes32)
    {
        return keccak256(abi.encode(address(this), account));
    }
    
    function _getEscrow(address account) internal view returns (address)
    {
        bytes32 salt = getSalt(account);
        return CREATE3.getDeployed(salt);
    }

    function isEscrowDeployed(address account) external view returns (bool)
    {
        address escrow = _getEscrow(account);
        uint256 size;
        assembly { size := extcodesize(escrow) }
        return size > 0;
    }

    function getEscrow(address account) external view returns (address)
    {
        return _getEscrow(account);
    }

    function deployEscrow(address account, uint256 tokenId) internal returns (address)
    {
        bytes32 salt = getSalt(account);
        return CREATE3.deploy(
                salt,
                abi.encodePacked(type(Escrow).creationCode, abi.encode(fee, account, address(this), rewardRouter, escrowController, tokenId)),
                0
            );
    }

    function createEscrow() external returns (address payable) {
        require(rewardRouter != address(0), "REWARD_ROUTER_NOT_SET");
        require(escrowController != address(0), "ESCROW_CONTROLLER_NOT_SET");
        address escrowAddress = this.getEscrow(msg.sender);
        require(RewardRouterV2(rewardRouter).pendingReceivers(msg.sender) == escrowAddress, "NO_SIGNALXFER_TO_ESCROW");
        uint256 nftId = IEscrowController(escrowController).mint(address(this), escrowAddress);
        address escrow = deployEscrow(msg.sender, nftId);
        Escrow(payable(escrow)).acceptTransferIn();
        //IEscrowController(escrowController).safeTransferFrom(address(this), escrow, nftId);
        IEscrowController(escrowController).safeTransferFrom(address(this), msg.sender, nftId);
        return payable(escrow);
    }

    function withdraw() external onlyOwner
    {
        owner.safeTransferETH(address(this).balance);
    }

    function transferControllerOwnership(address newOwner) external onlyOwner
    {
        IEscrowController(escrowController).transferOwnership(newOwner);
    }
}

