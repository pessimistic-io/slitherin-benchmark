// SPDX-License-Identifier: MIT
pragma solidity ^0.7.3;
pragma abicoder v2;
import "./IWETH9.sol";
import "./IVaultSwap.sol";

contract VaultSwap is IVaultSwap {
    // The WETH contract.
    IWETH9 public immutable WETH;
    // Creator of this contract.
    address public owner;
    // 0x ExchangeProxy address.
    // See https://docs.0x.org/developer-resources/contract-addresses
    address public exchangeProxy;

    constructor(IWETH9 _weth, address _exchangeProxy) {
        WETH = _weth;
        exchangeProxy = _exchangeProxy;
        owner = msg.sender;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "ONLY_OWNER");
        _;
    }

    // Payable fallback to allow this contract to receive protocol fee refunds.
    receive() external payable override {}

    // Swaps ERC20->ERC20 tokens held by this contract using a 0x-API quote.
    function swap(
        SwapParams calldata params
    )
        external
        payable
        override
        returns (uint256 boughtAmount)
    // Must attach ETH equal to the `value` field from the API response.
    {
        // Checks that the swapTarget is actually the address of 0x ExchangeProxy
        require(params.swapTarget == exchangeProxy, "Target not ExchangeProxy");
        require(params.sellToken != params.buyToken, "Same Token");

        uint256 protocolFee = msg.value;
        bool ethPayment;

        // Wrap ETH in WETH when needed
        // When sending ETH to the contract, the sellToken should be WETH
        if (
            address(params.sellToken) == address(WETH) &&
            msg.value >= params.sellAmount
        ) {
            WETH.deposit{value: params.sellAmount}();
            protocolFee = msg.value - params.sellAmount;
            ethPayment = true;
        } else {
            params.sellToken.transferFrom(
                msg.sender,
                address(this),
                params.sellAmount
            );
        }

        // Track our balance of the buyToken to determine how much we've bought.
        boughtAmount = params.buyToken.balanceOf(address(this));

        // Give `spender` an infinite allowance to spend this contract's `sellToken`.
        // Note that for some tokens (e.g., USDT, KNC), you must first reset any existing
        // allowance to 0 before being able to update it.
        require(params.sellToken.approve(params.spender, uint256(-1)));
        // Call the encoded swap function call on the contract at `swapTarget`,
        // passing along any ETH attached to this function call to cover protocol fees.
        (bool success, ) = params.swapTarget.call{value: protocolFee}(
            params.swapCallData
        );
        require(success, "SWAP_CALL_FAILED");

        // Use our current buyToken balance to determine how much we've bought.
        boughtAmount = params.buyToken.balanceOf(address(this)) - boughtAmount;

        // Transfer the amount bought
        params.buyToken.transfer(
            msg.sender,
            params.buyToken.balanceOf(address(this))
        );

        // Unwrap leftover WETH if crypto provided was ETH
        if (ethPayment) {
            WETH.withdraw(WETH.balanceOf(address(this)));
        }
        // Refund unswapped token back
        params.sellToken.transfer(
            msg.sender,
            params.sellToken.balanceOf(address(this))
        );
        // Refund any unspent protocol fees to the sender.
        msg.sender.transfer(address(this).balance);

        // Reset the approval
        params.sellToken.approve(params.spender, 0);
        emit Swap(params.sellToken, params.buyToken, boughtAmount);
        return boughtAmount;
    }
}

