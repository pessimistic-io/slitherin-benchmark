// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./ERC20.sol";
import "./SafeERC20.sol";
import "./SafeMath.sol";
import "./Ownable.sol";

contract PandaClaimPool is Ownable {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    mapping(address => uint256) public claimed;
    uint256 public constant tokenPerAddressMin = 1_500_000_000 * 10 ** 18;
    uint256 public constant tokenPerAddressMax = 1_600_000_000 * 10 ** 18;
    address private constant DEAD = address(0xdead);
    address private constant ARB_ADDRESS =
        0x912CE59144191C1204E64559FE8253a0e49E6548;

    uint256 public startTime;
    uint256 public endTime;
    address[] public whitelistAddresses;
    address public rewardToken;

    event Claim(uint256 tokenAmount, address to, uint256 timestamp);

    function random(uint256 min, uint256 max) internal view returns (uint256) {
        uint256 blockNumber = block.number - 1;
        uint256 blockHash = uint256(blockhash(blockNumber));
        uint256 randomNum = uint256(
            keccak256(abi.encodePacked(blockHash, block.timestamp))
        );
        return (randomNum % (max - min + 1)) + min;
    }

    function claimTokens() external {
        require(
            block.timestamp >= startTime && block.timestamp < endTime,
            "Claiming period has not started or has ended."
        );
        require(
            claimed[msg.sender] == 0,
            "You have already claimed your tokens."
        );
        uint256 arbBalance = IERC20(ARB_ADDRESS).balanceOf(address(this));
        require(
            isWhitelisted(msg.sender) || arbBalance > 0,
            "You are not in whitelist."
        );
        uint256 rewardRemain = IERC20(rewardToken).balanceOf(address(this));
        uint256 tokenAmount = random(tokenPerAddressMin, tokenPerAddressMax);
        require(rewardRemain >= tokenAmount, "out of reward tokens");

        claimed[msg.sender] = tokenAmount;
        IERC20(rewardToken).transfer(msg.sender, tokenAmount);

        emit Claim(tokenAmount, msg.sender, block.timestamp);
    }

    function isWhitelisted(address _address) public view returns (bool) {
        for (uint i = 0; i < whitelistAddresses.length; i++) {
            if (whitelistAddresses[i] == _address) {
                return true;
            }
        }
        return false;
    }

    function removeAddress(address _address) external onlyOwner {
        require(isWhitelisted(_address), "Address is not in whitelist");
        for (uint i = 0; i < whitelistAddresses.length; i++) {
            if (whitelistAddresses[i] == _address) {
                whitelistAddresses[i] = whitelistAddresses[
                    whitelistAddresses.length - 1
                ];
                whitelistAddresses.pop();
                break;
            }
        }
    }

    function setRewardTokenAddress(address _address) external onlyOwner {
        rewardToken = _address;
    }

    function setClaimTime(
        uint256 _startTime,
        uint256 _endTime
    ) external onlyOwner {
        startTime = _startTime;
        endTime = _endTime;
    }

    function burnRemainingToken() external onlyOwner {
        IERC20(rewardToken).transfer(
            DEAD,
            IERC20(rewardToken).balanceOf(address(this))
        );
    }
}

