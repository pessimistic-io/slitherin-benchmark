pragma solidity ^0.8.4;

// SPDX-License-Identifier: BUSL-1.1

import "./USDC.sol";
import "./Ownable.sol";

contract Faucet is Ownable {
    USDC public token;
    uint256 public amount;
    uint256 public startTimestamp;
    uint256 public fee = 1e15; // 0.001 ETH
    address public fee_collector;
    mapping(address => uint256) public lastSavedTimestamp;
    mapping(bytes32 => bool) public previousHashedMessages;

    constructor(USDC _token, address _fee_collector, uint256 _startTimestamp) {
        fee_collector = _fee_collector;
        token = _token;
        amount = 500 * (10 ** token.decimals());
        startTimestamp = _startTimestamp;
    }

    function claim() external payable {
        require(
            lastSavedTimestamp[msg.sender] == 0 ||
                (block.timestamp - startTimestamp) / 1 days >
                (lastSavedTimestamp[msg.sender] - startTimestamp) / 1 days,
            "Faucet: Already claimed!"
        );
        require(msg.value >= fee, "Faucet: Wrong fee");

        payable(fee_collector).transfer(fee);
        token.transfer(msg.sender, amount);
        lastSavedTimestamp[msg.sender] = block.timestamp;

        if (msg.value > fee) {
            payable(msg.sender).transfer(msg.value - fee);
        }
    }

    function withdraw() external onlyOwner {
        uint256 balance = token.balanceOf(address(this));
        token.transfer(owner(), balance);
    }

    /**
     * @notice Used for adjusting the amount of claimable tokens
     * @param value New amount of claimable tokens
     */
    function setAmount(uint256 value) external onlyOwner {
        amount = value;
    }

    /**
     * @notice Used for adjusting the fee to claim tokens
     * @param value New fee to claim tokens
     */
    function setFee(uint256 value) external onlyOwner {
        fee = value;
    }
}

