
//SPDX-License-Identifier: UNLICENSED

interface IGmxExchangeRouter {    
    struct CreateDepositParams {
        address receiver;
        address callbackContract;
        address uiFeeReceiver;
        address market;
        address initialLongToken;
        address initialShortToken;
        address[] longTokenSwapPath;
        address[] shortTokenSwapPath;
        uint256 minMarketTokens;
        bool shouldUnwrapNativeToken;
        uint256 executionFee;
        uint256 callbackGasLimit;
    }
    function sendWnt(address receiver,uint256 amount) external payable;
    function sendTokens(address token, address receiver, uint256 amount) external payable;
    function createDeposit(CreateDepositParams memory params) external payable  returns (bytes32);
    function multicall(bytes[] calldata data) external payable returns (bytes[] memory results);   
}
