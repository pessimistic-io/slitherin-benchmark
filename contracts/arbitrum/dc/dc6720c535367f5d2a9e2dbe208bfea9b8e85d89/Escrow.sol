// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.17;

import {SafeTransferLib} from "./SafeTransferLib.sol";
import {ERC721, ERC721TokenReceiver} from "./ERC721.sol";
import {RewardRouterV2} from "./IRewardRouterV2.sol";
import {IEscrowController} from "./IEscrowController.sol";

contract Escrow is ERC721TokenReceiver
{
    using SafeTransferLib for address;

    uint16 immutable public feeBasisPoints;
    address immutable public seller;
    address immutable public factory;
    address immutable public rewardRouter;
    address immutable public escrowController;
    uint256 immutable public tokenId;

    /// -----------------------------------------------------------------------
    /// Ownership Logic
    /// -----------------------------------------------------------------------

    function escrowOwner() internal view returns (address)
    {
        address nftOwner = ERC721(escrowController).ownerOf(tokenId);
        return nftOwner == address(0) ? factory : (nftOwner == address(this) ? seller : nftOwner);
    }

    modifier onlyEscrowOwner() {
        require(msg.sender == escrowOwner(), "Unauthorized");
        _;
    }

    constructor(uint16 fee, address sellerAddress, address factoryAddress, address router, address controller, uint256 id) {
        require (fee <= 10000, "FEE_TOO_LARGE");
        feeBasisPoints = fee;
        seller = sellerAddress;
        factory = factoryAddress;
        rewardRouter = router;
        escrowController = controller;
        tokenId = id; 
    }

    fallback() external payable { }

    receive() external payable { }

    function getSeller() external view returns (address)
    {
        return seller;
    }

    function getFactory() external view returns (address)
    {
        return factory;
    }

    function getTokenId() external view returns (uint256)
    {
        return tokenId;
    }

    function getFeeBPs() external view returns (uint16)
    {
        return feeBasisPoints;
    }


    function acceptTransferIn() external onlyEscrowOwner 
    {
        RewardRouterV2(rewardRouter).acceptTransfer(seller);
        //IEscrowController(escrowController).safeTransferFrom(address(this), seller, tokenId);
    }

    function signalTransferOut() external onlyEscrowOwner 
    {
        address recipient = escrowOwner();
        IEscrowController(escrowController).safeTransferFrom(recipient, address(this), tokenId);
        IEscrowController(escrowController).burn(tokenId);
        _claim();
        RewardRouterV2(rewardRouter).signalTransfer(recipient);
    }

    function claim() external onlyEscrowOwner 
    {
        _claim();
    }

    function _claim() internal
    {
        uint256 oldBalance = address(this).balance;
        bytes memory payload = abi.encodeCall(RewardRouterV2(rewardRouter).handleRewards, (false, false, true, true, true, true, true));
        (bool success, ) = address(rewardRouter).call(payload);
        success = success;
        uint256 devFee = (address(this).balance - oldBalance) * feeBasisPoints / 10000;
        factory.safeTransferETH(devFee);
        seller.safeTransferETH(address(this).balance);
    }
}
