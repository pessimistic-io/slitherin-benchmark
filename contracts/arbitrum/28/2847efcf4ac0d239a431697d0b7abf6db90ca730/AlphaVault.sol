// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "./Ownable.sol";
import "./IERC20.sol";

interface IWETH is IERC20 {
    function deposit() external payable;

    function withdraw(uint256 wad) external;
}

contract AlphaVaultSwap is Ownable {
    // AlphaVault custom events
    event WithdrawTokens(IERC20 buyToken, uint256 boughtAmount_);
    event EtherBalanceChange(uint256 wethBal_);
    event BadRequest(uint256 wethBal_, uint256 reqAmount_);
    event ZeroXCallSuccess(bool status, uint256 initialBuyTokenBalance);
    event buyTokenBought(uint256 buTokenAmount);
    event maxTransactionsChange(uint256 maxTransactions);

    /**
     * @dev Event to notify if transfer successful or failed
     * after account approval verified
     */
    event TransferSuccessful(
        address indexed from_,
        address indexed to_,
        uint256 amount_
    );

    error InvalidAddress();
    error Invalid_Multiswap_Data();
    error FillQuote_Swap_Failed(IERC20 buyToken,IERC20 sellToken);


    struct wethInfo{
        uint256 eth_balance;
        IWETH wETH;
    }
    // The WETH contract.
    IWETH public immutable WETH;
    // IERC20 ERC20Interface;

    uint256 public maxTransactions;
    uint256 public fee;
    // address private destination;

    constructor() {
        WETH = IWETH(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);
        maxTransactions = 25;
        fee = 5;
    }

    /**
     * @dev method that handles transfer of ERC20 tokens to other address
     * it assumes the calling address has approved this contract
     * as spender
     * @param amount numbers of token to transfer
     */
    function depositToken(IERC20 sellToken, uint256 amount) private {
        // require(amount > 0);
        // ERC20Interface = IERC20(sellToken);

        // if (amount > ERC20Interface.allowance(msg.sender, address(this))) {
        //     emit TransferFailed(msg.sender, address(this), amount);
        //     revert();
        // }

        // bool success = ERC20Interface.transferFrom(msg.sender, address(this), amount);
        sellToken.transferFrom(msg.sender, address(this), amount);
        emit TransferSuccessful(msg.sender, address(this), amount);
    }

    function setfee(uint256 num) external onlyOwner {
        fee = num;
    }

    function setMaxTransactionLimit(uint256 num) external onlyOwner {
        maxTransactions = num;
        emit maxTransactionsChange(maxTransactions);
    }

    // function withdrawFee(IERC20 token, uint256 amount) external onlyOwner{
    //     token.transfer(msg.sender, amount);
    // }

    // Transfer ETH held by this contrat to the sender/owner.
    function withdrawETH(uint256 amount) external onlyOwner {
        payable(msg.sender).transfer(amount);
    }

    // Payable fallback to allow this contract to receive protocol fee refunds.
    receive() external payable {}

    fallback() external payable {}

    // Transfer tokens held by this contrat to the sender/owner.
    function withdrawToken(IERC20 token, uint256 amount) internal {
        token.transfer(msg.sender, amount);
    }

    //Sets destination address to msg.sender
    function setDestination() internal view returns (address) {
        // destination = msg.sender;
        return msg.sender;
    }

    // Transfer amount of ETH held by this contrat to the sender.
    function transferEth(uint256 amount, address msgSender) internal {
        payable(msgSender).transfer(amount);
    }

    // Swaps ERC20->ERC20 tokens held by this contract using a 0x-API quote.
    function fillQuote(
        // The `buyTokenAddress` field from the API response.
        IERC20 buyToken,
        IERC20 sellToken,
        // The `allowanceTarget` field from the API response.
        address spender,
        // The `to` field from the API response.
        address swapTarget,
        // The `data` field from the API response.
        bytes calldata swapCallData
    ) internal returns (uint256) {
        if(spender == address(0)) revert InvalidAddress();
        // Track our balance of the buyToken to determine how much we've bought.
        uint256 boughtAmount = buyToken.balanceOf(address(this));
        sellToken.approve(spender, type(uint128).max);
        (bool success, ) = swapTarget.call{value: 0}(swapCallData);
        emit ZeroXCallSuccess(success, boughtAmount);
        if(!success) revert FillQuote_Swap_Failed({buyToken:buyToken,sellToken:sellToken});
        boughtAmount = buyToken.balanceOf(address(this)) - boughtAmount;
        emit buyTokenBought(boughtAmount);
        return boughtAmount;
    }

    /**
     * @param sellToken addresses of sell tokens
     * @param buyToken addresses of sell tokens
     * @param amount numbers of token to transfer  in unit256
     * 
     */
    function multiSwap(
        IERC20[] calldata sellToken,
        IERC20[] calldata buyToken,
        address[] calldata spender,
        address payable[] calldata swapTarget,
        bytes[] calldata swapCallData,
        uint256[] memory amount
    ) external payable {
        if(!(
            sellToken.length <= maxTransactions &&
                sellToken.length == buyToken.length &&
                spender.length == buyToken.length &&
                swapTarget.length == spender.length))
            revert Invalid_Multiswap_Data();

        wethInfo memory WethInfo= wethInfo(0,WETH);

        if (msg.value > 0) {
            WethInfo.wETH.deposit{value: msg.value}();
            WethInfo.eth_balance = msg.value-fee;
            WethInfo.wETH.transfer(owner(), fee);
            emit EtherBalanceChange(WethInfo.eth_balance);
        }

        for (uint256 i = 0; i < spender.length; i++) {
            // ETHER & WETH Withdrawl request.
            if (spender[i] == address(0)) {
                if (WethInfo.eth_balance < amount[i]) {
                    emit BadRequest(WethInfo.eth_balance, amount[i]);
                    break;
                }
                if (amount[i] > 0) {
                    WethInfo.eth_balance -= amount[i];
                    WethInfo.wETH.withdraw(amount[i]);
                    transferEth(amount[i], setDestination());
                    emit EtherBalanceChange(WethInfo.eth_balance);
                }
                continue;
            }
            // Condition For using Deposited Ether before using WETH From user balance.
            if (sellToken[i] == WethInfo.wETH) {
                if (sellToken[i] == buyToken[i]) {
                    depositToken(sellToken[i], amount[i]);
                    WethInfo.eth_balance += amount[i];
                    emit EtherBalanceChange(WethInfo.eth_balance);
                    continue;
                }
                WethInfo.eth_balance -= amount[i];
                emit EtherBalanceChange(WethInfo.eth_balance);
            } else {
                depositToken(sellToken[i], amount[i]);
            }

            // Variable to store amount of tokens purchased.
            uint256 boughtAmount = fillQuote(
                buyToken[i],
                sellToken[i],
                spender[i],
                swapTarget[i],
                swapCallData[i]
            );

            if (buyToken[i] == WethInfo.wETH) {
                WethInfo.eth_balance += boughtAmount;
                emit EtherBalanceChange(WethInfo.eth_balance);
            } else {
                withdrawToken(buyToken[i], boughtAmount);
                emit WithdrawTokens(buyToken[i], boughtAmount);
            }
        }
        if (WethInfo.eth_balance > 0) {
            withdrawToken(WethInfo.wETH, WethInfo.eth_balance);
            emit EtherBalanceChange(0);
        }
    }
}

