// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "./ReentrancyGuard.sol";
import "./ISwapRouter.sol";
import "./IUniswapV3Factory.sol";
import "./IHinkal.sol";
import "./Transferer.sol";
import "./CircomData.sol";
import "./IWrapper.sol";
import "./IFutureTransactExternalAction.sol";

contract FutureTransactExternalAction is Transferer, ReentrancyGuard, IFutureTransactExternalAction {
    mapping(bytes32 => bool) internal futureTransacts;

    address hinkalAddress;

    constructor(address _hinkalAddress) {
        hinkalAddress = _hinkalAddress;
    }

    function depositFutureTransact(
        address erc20TokenAddress,
        uint256 amount,
        address beneficiary,
        bytes memory metadata
    ) external payable {
        transferERC20TokenFromOrCheckETH(
            erc20TokenAddress,
            msg.sender,
            address(this),
            amount
        );

        bytes32 hash = buildFutureTransactHash(erc20TokenAddress, amount, beneficiary, metadata);
        require(!futureTransacts[hash], 'Unique violation for future transact');
        futureTransacts[hash] = true;

        emit NewFutureTransact(erc20TokenAddress, amount, beneficiary, metadata);
    }

    function runAction(
        CircomData memory circomData,
        bytes memory metadata
    ) external nonReentrant {
        require(circomData.relay == address(0), "relayer is not allowed");
        require(msg.sender == hinkalAddress, "only hinkal is allowed to call");
        bytes32 hash = buildFutureTransactHash(circomData.outErc20TokenAddress, circomData.outAmount, tx.origin, metadata);
        require(futureTransacts[hash], "provided future transact does not exists");
        delete futureTransacts[hash];

        transferERC20TokenOrETH(
            circomData.outErc20TokenAddress,
            hinkalAddress,
            circomData.outAmount
        );

        emit FutureTransactResolved(circomData.outErc20TokenAddress, circomData.outAmount, tx.origin, metadata);
    }

    function buildFutureTransactHash(
        address erc20TokenAddress,
        uint256 amount,
        address beneficiary,
        bytes memory metadata
    )
    pure
    private
    returns (bytes32)
    {
        return keccak256(abi.encodePacked(erc20TokenAddress, amount, beneficiary, metadata));
    }

    receive() external payable {}
}

