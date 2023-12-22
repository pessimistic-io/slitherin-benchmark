// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "./CircomData.sol";
import "./IExternalAction.sol";
import "./IWrapper.sol";
import "./IOdosRouter.sol";
import "./IHinkal.sol";
import "./Transferer.sol";
import "./console.sol";

contract OdosExternalAction is Transferer, IExternalAction {
  IOdosRouter public immutable swapRouter;
  address hinkalAddress;
  IWrapper public immutable wrapper;

  constructor(address _hinkalAddress, address swapRouterInstance, address wrapperAddress) {
    hinkalAddress = _hinkalAddress;
    swapRouter = IOdosRouter(swapRouterInstance);
    wrapper = IWrapper(wrapperAddress);
  }

  function runAction(CircomData memory circomData, bytes calldata metadata) external {
    (
      IOdosRouter.inputToken[] memory inputs,
      IOdosRouter.outputToken[] memory outputs,
      uint256 valueOutQuote,
      uint256 valueOutMin,
      address executor,
      bytes memory pathDefinition
    ) = abi.decode(
        metadata[4:],
        (IOdosRouter.inputToken[], IOdosRouter.outputToken[], uint256, uint256, address, bytes)
      );

    this.swapOdos(circomData, inputs, outputs, valueOutQuote, valueOutMin, executor, pathDefinition);
  }

  function swapOdos(
    CircomData memory circomData,
    IOdosRouter.inputToken[] memory inputs,
    IOdosRouter.outputToken[] memory outputs,
    uint256 valueOutQuote,
    uint256 valueOutMin,
    address executor,
    bytes calldata pathDefinition
  ) public returns (uint256 swapOutput) {
    console.log('valueOutQuote', valueOutQuote);
    console.log('valueOutMin', valueOutMin);
    console.log('executor', executor);
    console.log(circomData.inAmount);
    console.log('swapRouter', address(swapRouter));
    console.log(circomData.inErc20TokenAddress);

    wrapCoin(circomData);

    uint256 balance = getERC20OrETHBalance(circomData.inErc20TokenAddress);

    console.log('balance', balance);

    approveERC20Token(inputs[0].tokenAddress, address(swapRouter), inputs[0].amountIn);

    uint256 allowance = getERC20Allowance(inputs[0].tokenAddress, address(this), address(swapRouter));

    console.log('allowance', allowance);
    console.log('amount in', inputs[0].amountIn);
    console.log('in token address', inputs[0].tokenAddress);
    console.log('receiver', inputs[0].receiver);
    console.log('output receiver', outputs[0].receiver);

    console.log('before swap', circomData.outErc20TokenAddress);
    console.log(circomData.outAmount);

    (uint256[] memory amountsOut, uint256 gasLeft) = swapRouter.swap(
      inputs,
      outputs,
      valueOutQuote,
      valueOutMin,
      executor,
      pathDefinition
    );
    console.log('after swap', amountsOut[0]);

    swapOutput = amountsOut[0];

    unwrapCoinAndSend(circomData);
  }

  function wrapCoin(CircomData memory circomData) internal {
    require(
      circomData.inErc20TokenAddress != address(wrapper) && circomData.outErc20TokenAddress != address(wrapper),
      'native token wrapper forbidden'
    );
    if (circomData.inErc20TokenAddress == address(0)) {
      circomData.inErc20TokenAddress = address(wrapper);
      wrapper.deposit{value: circomData.inAmount}();
    }
    if (circomData.outErc20TokenAddress == address(0)) {
      circomData.outErc20TokenAddress = address(wrapper);
    }
  }

  function unwrapCoinAndSend(CircomData memory circomData) internal {
    if (circomData.outErc20TokenAddress == address(wrapper)) {
      wrapper.withdraw(circomData.outAmount);
      transferETH(hinkalAddress, circomData.outAmount);
    }
  }

  receive() external payable {}
}

