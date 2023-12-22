// SPDX-License-Identifier: MIT
import "./YCLPBase.sol";
import "./IERC20.sol";
import "./console.sol";

pragma solidity ^0.8.17;

// TODO: Go over the ERC20 Remove & add Liquidity.
// TODO: Then, implement the ETH ones throughtly.

contract YieldchainLPWrapper is YcLPer {
  /**
   * -------------------------------------------------------------
   * @notice Adds Liquidity to a standard LP Client (UNI-V2 Style) of a function that is either general (ERC20 & ETH) or specific (ERC20 only)
   * -------------------------------------------------------------
   */
  function _addLiquidityYC(
    Client memory client,
    address[] memory fromTokenAddresses,
    address[] memory toTokenAddresses,
    uint256[] memory fromTokenAmounts,
    uint256[] memory toTokenAmounts,
    uint256 slippage
  ) internal returns (uint256) {
    // Address of the current client
    address clientAddress = client.clientAddress;

    // Preparing Success & Result variables
    bool success;
    bytes memory result;

    // Payable sender
    address payable sender = payable(msg.sender);

    // Variable For Token A Balance
    uint256 tokenABalance = getTokenOrEthBalance(
      fromTokenAddresses[0],
      msg.sender
    );

    // Variable For Token B Balance
    uint256 tokenBBalance = getTokenOrEthBalance(
      toTokenAddresses[0],
      msg.sender
    );

    // Variable For Pair Address
    address pairAddress = getPairByClient(
      client,
      fromTokenAddresses[0],
      toTokenAddresses[0]
    );

    uint256 tokenAAmount;
    uint256 tokenBAmount;

    /**
     * Checking to see if one of the tokens is native ETH - assigning msg.value to it's amount variable, if so.
     * Reverting if the msg.value is 0 (No ETH sent)
     * @notice doing additional amount/balance checking as needed
     */
    if (fromTokenAddresses[0] == address(0)) {
      if (msg.value <= 0)
        revert('From Token is native ETH, but msg.value is 0');
      else tokenAAmount = msg.value;
    } else {
      // The amount inputted
      tokenAAmount = fromTokenAmounts[0];

      // If it's bigger than the user's balance, we assign the balance as the amount.
      if (tokenAAmount > tokenABalance) tokenAAmount = tokenABalance;

      // If it's equal to 0, we revert.
      if (tokenAAmount <= 0) revert('Token A Amount is Equal to 0');
    }

    /**
     * If the pair address is 0x0, it means that the pair does not exist yet - So we can use the inputted amounts
     */
    if (pairAddress == address(0)) {
      tokenAAmount = fromTokenAmounts[0];
      tokenBAmount = toTokenAmounts[0];
    } else {
      console.log('Pair Address: ', pairAddress);
      console.log('TokenA Amount', tokenAAmount);
      // Get amount out of the input amount of token A
      tokenBAmount = getAmountOutByClient(
        client,
        tokenAAmount,
        fromTokenAddresses[0],
        toTokenAddresses[0]
      );

      /**
       * @notice doing same native ETH check as before, but for token B.
       */
      if (toTokenAddresses[0] == address(0)) {
        // We revert if we got no msg.value if the address is native ETH
        if (msg.value <= 0)
          revert('To Token is native ETH, but msg.value is 0');

        // If msg.value is bigger than the token B amount, we will refund the difference
        if (msg.value > tokenBAmount) sender.transfer(msg.value - tokenBAmount);

        // Else, tokenBBalance is equal to msg.value (for next checks)
        tokenBBalance = msg.value;
      }

      // If the token B balance is smaller than the amount needed when adding out desired token A amount, we will decrement the token A amount
      // To be as much as possible when inserting the entire token B balance.
      if (tokenBBalance < tokenBAmount) {
        // Set the token B amount to the token B balance
        tokenBAmount = tokenBBalance;

        // Get the token A amount required to add the token B amount
        tokenAAmount = getAmountOutByClient(
          client,
          tokenBAmount,
          toTokenAddresses[0],
          fromTokenAddresses[0]
        );
      }
    }

    if (fromTokenAddresses[0] != address(0))
      // Transfer tokenA from caller to us
      IERC20(fromTokenAddresses[0]).transferFrom(
        msg.sender,
        address(this),
        tokenAAmount
      );

    if (fromTokenAddresses[0] != address(0))
      // Transfer tokenB from caller to us
      IERC20(toTokenAddresses[0]).transferFrom(
        msg.sender,
        address(this),
        tokenBAmount
      );

    // Approve the client to spend our tokens
    IERC20(fromTokenAddresses[0]).approve(clientAddress, tokenAAmount);
    IERC20(toTokenAddresses[0]).approve(clientAddress, tokenBAmount);

    if (
      (fromTokenAddresses[0] != address(0) &&
        toTokenAddresses[0] != address(0)) || client.isSingleFunction
    ) {
      // Add the liquidity now, and get the amount of LP tokens received. (We will return this)
      (success, result) = clientAddress.call{ value: msg.value }(
        abi.encodeWithSignature(
          client.erc20FunctionSig,
          fromTokenAddresses[0],
          toTokenAddresses[0],
          tokenAAmount,
          tokenBAmount,
          tokenAAmount - (tokenAAmount - tokenAAmount / (100 / slippage)), // slippage
          tokenBAmount - (tokenBAmount - tokenBAmount / (100 / slippage)), // slippage
          msg.sender,
          block.number + block.number
        )
      );

      console.log('client erc20 sig', client.erc20FunctionSig);
      console.log('From Token Symbol', IERC20(fromTokenAddresses[0]).symbol());
      console.log('To Token Symbol', IERC20(toTokenAddresses[0]).symbol());
      console.log('Token A Amount', tokenAAmount);
      console.log('Token B Amount', tokenBAmount);
      console.log(
        'Token A Amount - Slippage',
        tokenAAmount - tokenAAmount / (100 / slippage)
      );
      console.log(
        'Token B Amount - Slippage',
        tokenBAmount - tokenBAmount / (100 / slippage)
      );
      console.log('To', msg.sender);
      console.log('Deadlline', block.number + block.number);
      console.log('Block Number', block.number);
    } else if (fromTokenAddresses[0] == address(0))
      // Add the liquidity now, and get the amount of LP tokens received. (We will return this)
      (success, result) = clientAddress.call{ value: msg.value }(
        abi.encodeWithSignature(
          client.ethFunctionSig,
          toTokenAddresses[0],
          tokenBAmount,
          tokenBAmount - tokenBAmount / (100 / slippage), // slippage
          msg.value - msg.value / (100 / slippage), // slippage
          msg.sender,
          block.number + block.number
        )
      );
    else if (toTokenAddresses[0] == address(0))
      (success, result) = clientAddress.call{ value: msg.value }(
        abi.encodeWithSignature(
          client.ethFunctionSig,
          fromTokenAddresses[0],
          tokenAAmount,
          tokenAAmount - tokenAAmount / (100 / slippage), // slippage
          msg.value - msg.value / (100 / slippage), // slippage
          msg.sender,
          block.number + block.number
        )
      );

    // Return Liquidity Amount
    console.log('Result: (LIne Under )');
    console.logBytes(result);
    require(
      success,
      'Transaction Reverted When Adding Liquidity Mister Penis Poop'
    );
    return abi.decode(result, (uint256));
  }

  // -------------------------------------------------------------
  // ---------------------- ADD LIQUIDITY -----------------------
  // -------------------------------------------------------------
  /**
   * @notice Add Liquidity to a Client
   * @param clientName The name of the client
   * @param fromTokenAddresses The addresses of the tokens to add liquidity with
   * @param toTokenAddresses The addresses of the tokens to add liquidity to
   * @param fromTokensAmounts The amounts of the tokens to add liquidity with
   * @param toTokensAmounts The amounts of the tokens to add liquidity to
   * @param slippage The slippage percentage
   * @param customArguments The custom arguments to pass to the client
   * @return lpTokensReceived The amount of LP tokens received
   * @dev if the client is a 'Non-Standard' client, the customArguments will be passed to the client in a delegate call to a custom impl contract.
   * otherwise, we call the standard YC function (tht will handle UNI-V2-style clients)
   */
  function addLiquidityYc(
    string memory clientName,
    address[] memory fromTokenAddresses,
    address[] memory toTokenAddresses,
    uint256[] memory fromTokensAmounts,
    uint256[] memory toTokensAmounts,
    uint256 slippage,
    bytes[] memory customArguments
  ) external payable returns (uint256 lpTokensReceived) {
    // Get the client
    Client memory client = clients[clientName];

    bool success;
    bytes memory result;

    // Sufficient Checks
    require(
      fromTokenAddresses[0] != toTokenAddresses[0],
      'Cannot add liquidity to the same token'
    );

    // If it is a 'Non-Standard' LP Function, we delegate the call to what should be a custom implementation contract
    if (!client.isStandard) {
      (success, result) = client.clientAddress.delegatecall(
        abi.encodeWithSignature(
          client.erc20FunctionSig,
          fromTokenAddresses,
          toTokenAddresses,
          fromTokensAmounts,
          toTokensAmounts,
          slippage,
          customArguments
        )
      );

      // If it is a 'Standard' LP Function, we call it with the parameters
    } else {
      lpTokensReceived = _addLiquidityYC(
        client,
        fromTokenAddresses,
        toTokenAddresses,
        fromTokensAmounts,
        toTokensAmounts,
        slippage
      );
    }
  }

  /**
   * -------------------------------------------------------------
   * @notice Removes Liquidity from a LP Client that has a single ERC20 Function. Cannot be non-standard (non-standards will handle
   * this on their own within their own implementation contract)
   * -------------------------------------------------------------
   */
  function _removeLiquidityYC(
    Client memory client,
    address[] memory fromTokenAddresses,
    address[] memory toTokenAddresses,
    uint256[] memory lpTokensAmounts
  ) internal returns (uint256[] memory removedTokensReceived) {
    // Address of the current client
    address clientAddress = client.clientAddress;

    // Preparing Success & Result variables
    bool success;
    bytes memory result;

    // Sender
    address payable sender = payable(msg.sender);

    address tokenAAddress = fromTokenAddresses[0];
    address tokenBAddress = toTokenAddresses[0];

    // The pair address
    address pair = getPairByClient(client, tokenAAddress, tokenBAddress);

    // LP Balance of msg.sender
    uint256 balance = getTokenOrEthBalance(tokenAAddress, sender);

    // Getting the amount of LP to be removed
    uint256 lpAmount = lpTokensAmounts[0];

    if (lpAmount > balance) revert('Do not have enough LP tokens to remove');

    // Transfer LP tokens to us
    IERC20(tokenAAddress).transferFrom(sender, address(this), lpAmount);

    // The reserves
    (uint256 reserveA, uint256 reserveB) = getReservesByClient(pair, client);

    // Getting the amount of Token A to be removed
    uint256 tokenAAmount = (lpAmount * reserveA) / (reserveA + reserveB);

    // Getting the amount of Token B to be removed
    uint256 tokenBAmount = (lpAmount * reserveB) / (reserveA + reserveB);

    // Approve the LP tokens to be removed
    IERC20(pair).approve(client.clientAddress, lpAmount + (lpAmount / 20)); // Adding some upper slippage just in case

    // Call the remove LP function

    // If it's "single function" or none of the addresses are native ETH, call the erc20 function sig.
    if (
      (fromTokenAddresses[0] != address(0) &&
        toTokenAddresses[0] != address(0)) || client.isSingleFunction
    )
      (success, result) = clientAddress.call(
        abi.encodeWithSignature(
          client.erc20FunctionSig,
          fromTokenAddresses[0],
          toTokenAddresses[0],
          lpAmount,
          tokenAAmount - tokenAAmount / 30, // slippage
          tokenBAmount - tokenBAmount / 30, // slippage
          sender,
          block.number + block.number
        )
      );

      // Else if the from token is native ETH
    else if (fromTokenAddresses[0] == address(0))
      (success, result) = clientAddress.call{ value: msg.value }(
        abi.encodeWithSignature(
          client.ethFunctionSig,
          toTokenAddresses[0],
          lpAmount,
          tokenBAmount - tokenBAmount / 30, // slippage
          msg.value - msg.value / 30, // slippage
          sender,
          block.number + block.number
        )
      );

      // Else if the to token is native ETH
    else if (toTokenAddresses[0] == address(0))
      (success, result) = clientAddress.call{ value: msg.value }(
        abi.encodeWithSignature(
          client.ethFunctionSig,
          fromTokenAddresses[0],
          lpAmount,
          tokenAAmount - tokenAAmount / 30, // slippage
          msg.value - msg.value / 30, // slippage
          sender,
          block.number + block.number
        )
      );

    // If the call was not successful, revert
    if (!success) revert('Call to remove liquidity failed');

    // If the call was successful, return the amount of tokens received
    removedTokensReceived = abi.decode(result, (uint256[]));
  }

  // -------------------------------------------------------------
  // ---------------------- REMOVE LIQUIDITY ---------------------
  // -------------------------------------------------------------
  /**
   * @notice Removes Liquidity from a LP Client,
   * @param clientName The name of the client
   * @param fromTokenAddresses The addresses of the tokens to be removed
   * @param toTokenAddresses The addresses of the tokens to be received
   * @param lpTokensAmounts The amount of LP tokens to be removed
   * @param customArguments Custom arguments to be passed to the client
   * @return removedTokensReceived The amount of tokens received
   * @dev If the client is classfied as non-standard, the call will be delegated to the client's implementation contract.
   * Otherwise, it will be called as a standard UNI-V2 style LP.
   */
  function removeLiquidityYc(
    string memory clientName,
    address[] memory fromTokenAddresses,
    address[] memory toTokenAddresses,
    bytes[] memory customArguments,
    uint256[] memory lpTokensAmounts
  ) public returns (uint256[] memory) {
    bool success;
    bytes memory result;
    // Client Functions
    Client memory client = clients[clientName];

    // If it is a 'Non-Standard' LP Function, we delegate the call to what should be a custom implementation contract
    if (!client.isStandard) {
      (success, result) = client.clientAddress.delegatecall(
        abi.encodeWithSignature(
          client.erc20FunctionSig,
          fromTokenAddresses,
          toTokenAddresses,
          lpTokensAmounts,
          customArguments
        )
      );
      return abi.decode(result, (uint256[]));
    }

    // Otherwise, call the standard function (UNI-V2 Style)
    return
      _removeLiquidityYC(
        client,
        fromTokenAddresses,
        toTokenAddresses,
        lpTokensAmounts
      );
  }
}

