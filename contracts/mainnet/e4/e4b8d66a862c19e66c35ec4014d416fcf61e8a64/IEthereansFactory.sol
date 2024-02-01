// SPDX-License-Identifier: MIT
pragma solidity >=0.7.0;

import "./IFactory.sol";
import "./IERC1155Receiver.sol";

interface IEthereansFactory is IFactory {

    struct EthereansFactoryInitializer {
        uint256 feePercentageForTransacted;
        address feeReceiver;
        address tokenToTransferOrBurnAddressInCreation;
        uint256 transferOrBurnAmountInCreation;
        address transferOrBurnReceiverInCreation;
        address tokenToTransferOrBurnAddressInApplication;
        uint256 transferOrBurnAmountInApplication;
        address transferOrBurnReceiverInApplication;
        bytes factoryLazyInitData;
    }

    function feeInfo() external view returns(address operator, uint256 feePercentageForTransacted, address feeReceiver, address tokenToTransferOrBurnAddressInCreation, uint256 transferOrBurnAmountInCreation, address transferOrBurnReceiverInCreation, address tokenToTransferOrBurnAddressInApplication, uint256 transferOrBurnAmountInApplication, address transferOrBurnReceiverInApplication);

    function payFee(address sender, address tokenAddress, uint256 value, bytes calldata permitSignature) external payable returns (uint256 feePaid);
    function burnOrTransferToken(address sender, bytes calldata permitSignature) external payable returns(uint256 amountTransferedOrBurnt);
}
