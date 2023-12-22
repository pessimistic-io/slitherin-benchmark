// SPDX-License-Identifier: MIT
// copyright ZipSwap 2022

pragma solidity ^0.8.11;
import "./IERC20.sol";
import "./Pausable.sol";
import "./BoringERC20.sol";
import { Ownable } from "./Ownable.sol";
import { SafeTransferEth } from "./SafeTransferEth.sol";



interface IClaimVerifier {
    function verify_claim(address to, uint amount, bytes calldata signature) external returns (bool valid);
}

contract NyanBridge is Ownable {
    IERC20 immutable public nyan;
    IClaimVerifier verifier;
    
    mapping(address => uint) public nyanSentOut;
    uint public totalNyanSentOut;

    struct ReceiveInfo {
        uint totalAmount;
        uint128 lastDepositTime;
        uint128 lastDepositBlockNumber;
    }
    mapping(address => ReceiveInfo) public nyanReceived;
    uint public totalNyanReceived;

    bool public depositsPaused;
    bool public withdrawalsPaused;

    event NyanClaimed(address indexed to, uint amount, uint totalAmount);
    event NyanReceived(address indexed from, address indexed targetAddress, uint amount);

    constructor(IERC20 _nyan, IClaimVerifier _verifier) {
        nyan = _nyan;
        verifier = _verifier;
    }

    function getNyan(address to, uint totalAmount, bytes calldata signature) external {
        require(!depositsPaused, 'withdrawals paused');
    
        uint sentAmount = nyanSentOut[to];
        require(sentAmount < totalAmount, 'nothing to claim');
        require(verifier.verify_claim(to, totalAmount, signature), 'invalid signature');
        uint amountDiff = totalAmount-sentAmount;
        nyanSentOut[to] = totalAmount;
        totalNyanSentOut += amountDiff;
        require(nyan.transfer(to, amountDiff));

        emit NyanClaimed(to, amountDiff, totalAmount);
    }

    function sendNyan(address to, uint amount) public {
        require(!withdrawalsPaused, 'deposits paused');

        require(nyan.transferFrom(msg.sender, address(this), amount));
        ReceiveInfo storage _nyanReceived = nyanReceived[to];
        _nyanReceived.totalAmount += amount;
        _nyanReceived.lastDepositTime = uint128(block.timestamp);
        _nyanReceived.lastDepositBlockNumber = uint128(block.number);
        totalNyanReceived += amount;
    }

    function sendNyanWithPermit(address to, uint amount, uint deadline, uint8 v, bytes32 r, bytes32 s) external {
        nyan.permit(msg.sender, address(this), amount, deadline, v, r, s);
        sendNyan(to, amount);
    }

    function timestamp() external view returns (uint time) {
        return block.timestamp;
    }

    // owner functions

    function setVerifier(IClaimVerifier newVerifier) external onlyOwner {
        verifier = newVerifier;
    }

    function setPause(bool pauseDeposits, bool pauseWithdrawals) external onlyOwner {
        depositsPaused = pauseDeposits;
        withdrawalsPaused = pauseWithdrawals;
    }

    function setNyanSentOut(address user, uint amount) external onlyOwner {
        nyanSentOut[user] = amount;
    }

    function withdrawEth() external onlyOwner {
        SafeTransferEth.transferEth(msg.sender, address(this).balance);
    }

    function withdrawToken(IERC20 _token, address recipient, uint amount) external onlyOwner returns (uint) {
        if(amount == 0) {
            amount = _token.balanceOf(address(this));
        }
        BoringERC20.safeTransfer(_token, recipient, amount);
        return amount;
    }
}
