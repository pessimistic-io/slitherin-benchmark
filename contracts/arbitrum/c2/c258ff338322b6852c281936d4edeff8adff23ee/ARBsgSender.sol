// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.18;

//import "layerzerolabs/contracts/token/oft/OFT.sol";
import "./IStargateRouter.sol";
import "./TransferHelper.sol";
import "./IERC20.sol";
import {Ownable} from "./Ownable.sol";


interface ISGETH is IERC20{
    function deposit() payable external;
}

contract SgSender is Ownable {

    //Constants
    address public constant stargateRouterAddress = 0x53Bf833A5d6c4ddA888F69c22C88C9f356a41614; //https://stargateprotocol.gitbook.io/stargate/developers/contract-addresses/mainnet
    address public constant sgethAddress = 0x82CbeCF39bEe528B5476FE6d1550af59a9dB6Fc0;
    uint16 public constant dstChainId = 101; //https://stargateprotocol.gitbook.io/stargate/developers/contract-addresses/mainnet
    uint16 public constant srcPoolId = 13;   //https://stargateprotocol.gitbook.io/stargate/developers/contract-addresses/mainnet
    uint16 public constant dstPoolId = 13;   //https://stargateprotocol.gitbook.io/stargate/developers/contract-addresses/mainnet

    //Mutable variables
    address public sgReceiverAddress; //destination contract. it must implement sgReceive()
    bool public paused = false;

    event PauseToggled(bool paused);
    event SgReceiverChanged(address sgReceiverAddress);
    event UnshethMinted(address indexed sender, uint256 amount, uint256 min_amount_stargate, uint256 min_amount_unshethZap, uint256 dstGasForCall, uint256 dstNativeAmount, uint256 unsheth_path);

    constructor(
        address _owner, //desired owner (e.g. multisig)
        address _sgReceiver //address of the sgReceiver deployed on ETH
    ) {
        sgReceiverAddress = _sgReceiver;
        //approve sgeth for spending by stargateRouter
        TransferHelper.safeApprove(sgethAddress, stargateRouterAddress, type(uint256).max);
        //transfer ownership to desired owner
        transferOwnership(_owner);
    }

    modifier onlyWhenUnpaused {
        require(paused == false, "Contract is paused");
        _;
    }

    // owner function that sets the pause parameter
    function togglePaused() public onlyOwner {
        paused = !paused;
        emit PauseToggled(paused);
    }

    function changeSgReceiver(address _sgReceiver) public onlyOwner {
        require(_sgReceiver != address(0), "sgReceiver cannot be zero address");
        sgReceiverAddress = _sgReceiver;
        emit SgReceiverChanged(_sgReceiver);
    }

    // mint_unsheth function that sends ETH to the sgReceiver on Mainnet contract to mint unshETH tokens
    function mint_unsheth(
        uint256 amount,                         // the amount of ETH
        uint256 min_amount_stargate,            // the minimum amount of ETH to receive on stargate,
        uint256 min_amount_unshethZap,          // the minimum amount of unshETH to receive from the unshETH Zap
        uint256 dstGasForCall,                  // the amount of gas to send to the sgReceive contract
        uint256 dstNativeAmount,                // leftover eth that will get airdropped to the sgReceive contract
        uint256 unsheth_path                    // the path that the unsheth Zap will take to mint unshETH
    ) external payable onlyWhenUnpaused {
        // ensure the msg.value is greater than the amount of ETH being sent
        require(msg.value > amount, "Not enough ETH provided as msg.value");

        // deposit the ETH into the sgeth contract
        ISGETH(sgethAddress).deposit{value:amount}();

        //calculate the fee that will be used to pay for the swap 
        uint256 feeAmount = msg.value - amount;

        bytes memory data = abi.encode(msg.sender, min_amount_unshethZap, unsheth_path);

        // Encode payload data to send to destination contract, which it will handle with sgReceive()
        IStargateRouter(stargateRouterAddress).swap{value:feeAmount}( //call estimateGasFees to get the msg.value
            dstChainId,                                               // the destination chain id - ETH
            srcPoolId,                                                // the source Stargate poolId
            dstPoolId,                                                // the destination Stargate poolId
            payable(msg.sender),                                      // refund address. if msg.sender pays too much gas, return extra ETH to this address
            amount,                                                   // total tokens to send to destination chain
            min_amount_stargate,                                      // min amount allowed out
            IStargateRouter.lzTxObj(dstGasForCall, dstNativeAmount, abi.encodePacked(sgReceiverAddress)), // default lzTxObj
            abi.encodePacked(sgReceiverAddress),                      // destination address, the sgReceive() implementer
            data                                                      // bytes payload which sgReceive() will parse into an address that the unshETH will be sent too.
        );

        emit UnshethMinted(msg.sender, amount, min_amount_stargate, min_amount_unshethZap, dstGasForCall, dstNativeAmount, unsheth_path);
    }
}
