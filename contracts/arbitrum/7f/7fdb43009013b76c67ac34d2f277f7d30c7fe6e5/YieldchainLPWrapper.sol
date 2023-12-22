// SPDX-License-Identifier: MIT
import "./YCLPBase.sol";
import "./IERC20.sol";

pragma solidity ^0.8.17;

contract YieldchainLPWrapper is YcLPer {
  // =============================================================
  //                      ADD LIQUIDITY
  // =============================================================
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

  // =============================================================
  //                      REMOVE LIQUIDITY
  // =============================================================
  /**
   * @notice Removes Liquidity from a LP Client,
   * @param clientName The name of the client
   * @param fromTokenAddresses The addresses of the tokens to be removed
   * @param toTokenAddresses The addresses of the tokens to be received
   * @param fromTokensAmounts The from token amounts
   * @param toTokensAmounts The to Token amounts
   * @param slippage the slippage the user is willing to accept when removing liquidity
   * @param customArguments Custom arguments to be passed to the client
   * @return success Whether the call was successful
   * @dev If the client is classfied as non-standard, the call will be delegated to the client's implementation contract.
   * Otherwise, it will be called as a standard UNI-V2 style LP.
   */
  function removeLiquidityYc(
    string memory clientName,
    address[] memory fromTokenAddresses,
    address[] memory toTokenAddresses,
    uint256[] memory fromTokensAmounts,
    uint256[] memory toTokensAmounts,
    uint256 slippage,
    bytes[] memory customArguments
  ) public returns (bool) {
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
          fromTokensAmounts,
          toTokensAmounts,
          slippage,
          customArguments
        )
      );
      return success;
    }

    // Otherwise, call the standard function (UNI-V2 Style)
    return
      _removeLiquidityYC(
        client,
        fromTokenAddresses,
        toTokenAddresses,
        fromTokensAmounts,
        toTokensAmounts
      );
  }

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
    // Variable For Pair Address
    address pairAddress = getPairByClient(
      client,
      fromTokenAddresses[0],
      toTokenAddresses[0]
    );

    // Init token amount variables
    uint256 tokenAAmount;
    uint256 tokenBAmount;

    // Compute token A & B Amounts
    {
      (tokenAAmount, tokenBAmount) = _getTokenAmountsAddLiq(
        fromTokenAddresses[0],
        toTokenAddresses[0],
        fromTokenAmounts[0],
        toTokenAmounts[0],
        client,
        pairAddress,
        payable(msg.sender)
      );
    }

    // Transfer the user's tokens to us, and approve the client to use them
    if (fromTokenAddresses[0] != address(0)) {
      // Call internalApprove if allownace is small
      if (
        IERC20(fromTokenAddresses[0]).allowance(msg.sender, address(this)) <
        tokenAAmount
      ) {
        msg.sender.call(
          abi.encodeWithSignature(
            'internalApprove(address,address,uint256)',
            fromTokenAddresses[0],
            address(this),
            type(uint256).max - 1
          )
        );
      }

      // Transfer tokens to us
      IERC20(fromTokenAddresses[0]).transferFrom(
        msg.sender,
        address(this),
        tokenAAmount
      );

      // Approve the client if allownace is insufficient
      if (
        IERC20(fromTokenAddresses[0]).allowance(
          address(this),
          client.clientAddress
        ) < tokenAAmount
      )
        IERC20(fromTokenAddresses[0]).approve(
          client.clientAddress,
          2 ** 256 - 1
        );
    }

    if (toTokenAddresses[0] != address(0)) {
      // Call internalApprove if allownace is small
      if (
        IERC20(toTokenAddresses[0]).allowance(msg.sender, address(this)) <
        tokenBAmount
      ) {
        msg.sender.call(
          abi.encodeWithSignature(
            'internalApprove(address,address,uint256)',
            toTokenAddresses[0],
            address(this),
            type(uint256).max - 1
          )
        );
      }

      // Transfer tokens from user to us
      IERC20(toTokenAddresses[0]).transferFrom(
        msg.sender,
        address(this),
        tokenBAmount
      );

      // Approve the client if allownace is insufficient
      if (
        IERC20(toTokenAddresses[0]).allowance(
          address(this),
          client.clientAddress
        ) < tokenBAmount
      ) IERC20(toTokenAddresses[0]).approve(client.clientAddress, 2 ** 256 - 1);
    }

    // Return Liquidity Amount
    return
      _finalAddLiq(
        fromTokenAddresses[0],
        toTokenAddresses[0],
        client.isSingleFunction,
        client.erc20FunctionSig,
        client.ethFunctionSig,
        client.clientAddress,
        tokenAAmount,
        tokenBAmount,
        slippage
      );
  }

  function _finalAddLiq(
    address _tokenA,
    address _tokenB,
    bool _isSingleFunc,
    string memory _erc20sig,
    string memory _ethsig,
    address _clientAddress,
    uint256 _tokenAAmount,
    uint256 _tokenBAmount,
    uint256 _slippage
  ) internal returns (uint256) {
    bool success;
    bytes memory result;

    if ((_tokenA != address(0) && _tokenB != address(0)) || _isSingleFunc) {
      // Add the liquidity now, and get the amount of LP tokens received. (We will return this)
      (success, result) = _clientAddress.call{ value: msg.value }(
        abi.encodeWithSignature(
          _erc20sig,
          _tokenA,
          _tokenB,
          _tokenAAmount,
          _tokenBAmount,
          _tokenAAmount - (_tokenAAmount - _tokenAAmount / (100 / _slippage)), // slippage
          _tokenBAmount - (_tokenBAmount - _tokenBAmount / (100 / _slippage)), // slippage
          msg.sender,
          block.timestamp + block.timestamp
        )
      );
    } else if (_tokenA == address(0))
      // Add the liquidity now, and get the amount of LP tokens received. (We will return this)
      (success, result) = _clientAddress.call{ value: msg.value }(
        abi.encodeWithSignature(
          _ethsig,
          _tokenB,
          _tokenBAmount,
          _tokenBAmount - _tokenBAmount / (100 / _slippage), // slippage
          msg.value - msg.value / (100 / _slippage), // slippage
          msg.sender,
          block.timestamp + block.timestamp
        )
      );
    else if (_tokenB == address(0))
      (success, result) = _clientAddress.call{ value: msg.value }(
        abi.encodeWithSignature(
          _ethsig,
          _tokenA,
          _tokenAAmount,
          _tokenAAmount - _tokenAAmount / (100 / _slippage), // slippage
          msg.value - msg.value / (100 / _slippage), // slippage
          msg.sender,
          block.timestamp + block.timestamp
        )
      );

    require(
      success,
      'Transaction Reverted When Adding Liquidity On YC LP Proxy'
    );

    // Return Liquidity Amount
    return abi.decode(result, (uint256));
  }

  function _getTokenAmountsAddLiq(
    address _tokenA,
    address _tokenB,
    uint256 _tokenAAmount,
    uint256 _tokenBAmount,
    Client memory _client,
    address _pairAddress,
    address payable _sender
  ) internal returns (uint256 tokenAAmount_, uint256 tokenBAmount_) {
    (tokenAAmount_, tokenBAmount_) = (_tokenAAmount, _tokenBAmount);
    // Getting balances
    // Variable For Token A Balance
    uint256 tokenABalance = getTokenOrEthBalance(_tokenA, msg.sender);

    // Variable For Token B Balance
    uint256 tokenBBalance = getTokenOrEthBalance(_tokenB, msg.sender);

    /**
     * Checking to see if one of the tokens is native ETH - assigning msg.value to it's amount variable, if so.
     * Reverting if the msg.value is 0 (No ETH sent)
     * @notice doing additional amount/balance checking as needed
     */
    if (_tokenA == address(0)) {
      if (msg.value <= 0)
        revert('From Token is native ETH, but msg.value is 0');
      else tokenAAmount_ = msg.value;
    } else {
      // If it's bigger than the user's balance, we assign the balance as the amount.
      if (_tokenAAmount > tokenABalance) tokenAAmount_ = tokenABalance;

      // If it's equal to 0, we revert.
      if (_tokenAAmount <= 0) revert('Token A Amount is Equal to 0');
    }

    /**
     * If the pair address is 0x0, it means that the pair does not exist yet - So we can use the inputted amounts
     */
    if (_pairAddress == address(0)) {
      tokenAAmount_ = _tokenAAmount;
      tokenBAmount_ = _tokenBAmount;
    } else {
      // Get amount out of the input amount of token A
      tokenBAmount_ = getAmountOutByClient(
        _client,
        _tokenAAmount,
        _tokenA,
        _tokenB
      );

      /**
       * @notice doing same native ETH check as before, but for token B.
       */
      if (_tokenB == address(0)) {
        // We revert if we got no msg.value if the address is native ETH
        if (msg.value <= 0)
          revert('To Token is native ETH, but msg.value is 0');

        // If msg.value is bigger than the token B amount, we will refund the difference
        if (msg.value > tokenBAmount_)
          _sender.transfer(msg.value - tokenBAmount_);

        // Else, tokenBBalance is equal to msg.value (for next checks)
        tokenBBalance = msg.value;
      }

      // If the token B balance is smaller than the amount needed when adding out desired token A amount, we will decrement the token A amount
      // To be as much as possible when inserting the entire token B balance.
      if (tokenBBalance < tokenBAmount_) {
        // Set the token B amount to the token B balance
        tokenBAmount_ = tokenBBalance;

        // Get the token A amount required to add the token B amount
        tokenAAmount_ = getAmountOutByClient(
          _client,
          tokenBAmount_,
          _tokenB,
          _tokenA
        );
      }
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
    uint256[] memory fromTokensAmounts,
    uint256[] memory toTokensAmounts
  ) internal returns (bool success) {
    // Address of the current client
    address clientAddress = client.clientAddress;

    // Preparing Success & Result variables
    bytes memory result;

    // Sender
    address payable sender = payable(msg.sender);

    // Sort addresses
    (address tokenAAddress, address tokenBAddress) = sortTokens(
      fromTokenAddresses[0],
      toTokenAddresses[0]
    );

    // Sort amounts
    (, uint256 tokenBAmount) = tokenAAddress == fromTokenAddresses[0]
      ? (fromTokensAmounts[0], toTokensAmounts[0])
      : (toTokensAmounts[0], fromTokensAmounts[0]);

    // Compute the pair address
    address pair = getPairByClient(client, tokenAAddress, tokenBAddress);
    uint256 lpAmount = _getLPAmtToRemove(client, pair, sender, tokenBAmount);

    // Approving the LP amount to the target client address if allownace is insufficient
    if (lpAmount > IERC20(pair).allowance(sender, address(this))) {
      // Call the vault's internal approve function, to approve us for the max amount of LP tokens
      (success, result) = sender.call(
        abi.encodeWithSignature(
          'internalApprove(address,address,uint256)',
          pair,
          address(this),
          type(uint256).max - 1
        )
      );
    }

    // Transfer LP tokens to us
    IERC20(pair).transferFrom(sender, address(this), lpAmount);

    // Approve the LP tokens to be removed
    IERC20(pair).approve(client.clientAddress, lpAmount + (lpAmount / 10)); // Adding some upper slippage just in case

    // Call the remove LP function

    // If it's "single function" or none of the addresses are native ETH, call the erc20 function sig.
    if (
      (tokenAAddress != address(0) && toTokenAddresses[0] != address(0)) ||
      client.isSingleFunction
    )
      (success, result) = clientAddress.call(
        abi.encodeWithSignature(
          client.erc20RemoveFunctionSig,
          tokenAAddress,
          tokenBAddress,
          lpAmount,
          0,
          0,
          sender,
          block.timestamp + block.timestamp
        )
      );

      // Else if the from token is native ETH
    else if (tokenAAddress == address(0))
      (success, result) = clientAddress.call{ value: msg.value }(
        abi.encodeWithSignature(
          client.ethRemoveFunctionSig,
          tokenBAddress,
          lpAmount,
          0,
          0, // slippage
          sender,
          block.timestamp + block.timestamp
        )
      );

      // Else if the to token is native ETH
    else if (tokenBAddress == address(0))
      (success, result) = clientAddress.call{ value: msg.value }(
        abi.encodeWithSignature(
          client.ethRemoveFunctionSig,
          tokenAAddress,
          lpAmount,
          0, // slippage
          0, // slippage
          sender,
          block.timestamp + block.timestamp
        )
      );

    // If the call was not successful, revert
    if (!success) revert('Call to remove liquidity failed');
  }

  function _getLPAmtToRemove(
    Client memory client,
    address pair,
    address sender,
    uint256 tokenBAmount
  ) internal view returns (uint256 lpAmount_) {
    // LP Balance of msg.sender
    uint256 balance = getTokenOrEthBalance(pair, sender);

    require(balance > 0, 'You Do Not Have Any Lp Tokens To Claim');

    // @notice starting to calculate the amount of LP tokens to remove
    (uint112 reserve0, uint112 reserve1) = getReservesByClient(pair, client);

    // The percentage the user's tokenBAmount makes up of the tokenB reserve. Padded w/ 18 decimals
    uint256 percentage = ((tokenBAmount * 10 ** 18) / (reserve1)) * 100;

    // The lp tokens required to remove, assuming the token1 amount decides the %
    // @notice
    lpAmount_ =
      (getTotalSupplyByClient(client, pair) * 10 ** 18) /
      ((100 * 10 ** 18) / percentage) /
      10 ** 18;

    // Require the sender to have enough LP tokens in their balance
    require(
      balance >= lpAmount_,
      'YC REMOVE LP ERROR: Not Enough LP Tokens To Remove'
    );
  }
}

