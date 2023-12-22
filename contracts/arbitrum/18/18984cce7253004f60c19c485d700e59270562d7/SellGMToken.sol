/*
    Copyright 2022 JOJO Exchange
    SPDX-License-Identifier: BUSL-1.1*/
pragma solidity 0.8.9;


import "./SafeERC20.sol";
import "./GmxInterface.sol";
import "./Ownable.sol";

contract SellGMToken is Ownable{
    
    
    using SafeERC20 for IERC20;

    address public router;
    address public exchangeRoute;
    address public withdrawalVault;

    constructor(
        address _router,
        address _withdrawalVault,
        address _exchangeRoute
    ) {
        router = _router;
        withdrawalVault = _withdrawalVault;
        exchangeRoute = _exchangeRoute;
    }


    function getSendWntData(address receiver, uint256 amount) public  pure returns (bytes memory){
        return 
            abi.encodeWithSignature(
                "sendWnt(address,uint256)",
                receiver,
                amount
            );
    }


    function getSendTokens(address token, address reciver, uint256 amount) public  pure returns (bytes memory){
        return 
            abi.encodeWithSignature(
                "sendTokens(address,address,uint256)",
                token,
                reciver,
                amount
            );
    }


    function getCreateWithdrawal (GmxInterface.CreateWithdrawalParams memory param) public  pure returns (bytes memory){
        return 
            abi.encodeWithSignature(
                "createWithdrawal((address,address,address,address,address[],address[],uint256,uint256,bool,uint256,uint256))",
                param
            );
    }

    function refund(address token) public onlyOwner{

        uint256 tokenAmount = IERC20(token).balanceOf(address(this));
        IERC20(token).transfer(owner(), tokenAmount);

    }

    function sellToken(
        address gmToken,
        uint256 gmAmount,
        uint256 ethAmount,
        address to
    ) payable external {
        IERC20(gmToken).safeTransferFrom(msg.sender, address(this), gmAmount);
        IERC20(gmToken).safeApprove(router, gmAmount);

        bytes[] memory data = new bytes[](3);

        data[0] = getSendWntData(withdrawalVault, ethAmount);
        data[1] = getSendTokens(gmToken, withdrawalVault, gmAmount);

        GmxInterface.CreateWithdrawalParams memory param;
        param.receiver = to;
        param.callbackContract = 0x0000000000000000000000000000000000000000;
        param.uiFeeReceiver = 0x0000000000000000000000000000000000000000;
        param.market = gmToken;
        param.longTokenSwapPath = new address[](0);
        param.shortTokenSwapPath = new address[](0);
        param.minLongTokenAmount = 0;
        param.minShortTokenAmount = 0;
        param.shouldUnwrapNativeToken = false;
        param.executionFee = ethAmount;
        param.callbackGasLimit = 0;
        data[2] = getCreateWithdrawal(param);

        GmxInterface(exchangeRoute).multicall{value: ethAmount}(data);
    }
}

